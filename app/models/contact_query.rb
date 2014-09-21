# This file is a part of Redmine CRM (redmine_contacts) plugin,
# customer relationship management plugin for Redmine
#
# Copyright (C) 2011-2014 Kirill Bezrukov
# http://www.redminecrm.com/
#
# redmine_contacts is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_contacts is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_contacts.  If not, see <http://www.gnu.org/licenses/>.

class ContactQuery < Query

  self.queried_class = Contact

  self.available_columns = [
    QueryColumn.new(:name, :sortable => "#{Contact.table_name}.last_name, #{Contact.table_name}.first_name", :caption => :field_contact_full_name),
    QueryColumn.new(:first_name, :sortable => "#{Contact.table_name}.first_name"),
    QueryColumn.new(:last_name, :sortable => "#{Contact.table_name}.last_name"),
    QueryColumn.new(:middle_name, :sortable => "#{Contact.table_name}.middle_name", :caption => :field_contact_middle_name),
    QueryColumn.new(:job_title, :sortable => "#{Contact.table_name}.job_title", :caption => :field_contact_job_title, :groupable => true),
    QueryColumn.new(:company, :sortable => "#{Contact.table_name}.company", :groupable => "#{Contact.table_name}.company", :caption => :field_contact_company, :groupable => true),
    QueryColumn.new(:phones, :sortable => "#{Contact.table_name}.phone", :caption => :field_contact_phone),
    QueryColumn.new(:emails, :sortable => "#{Contact.table_name}.email", :caption => :field_contact_email),
    QueryColumn.new(:city, :sortable => "#{Address.table_name}.city", :groupable => "#{Address.table_name}.city", :caption => :label_crm_city),
    QueryColumn.new(:region, :sortable => "#{Address.table_name}.region", :caption => :label_crm_region),
    QueryColumn.new(:postcode, :sortable => "#{Address.table_name}.postcode", :caption => :label_crm_postcode),
    QueryColumn.new(:country, :sortable => "#{Address.table_name}.country_code", :groupable => "#{Address.table_name}.country_code", :caption => :label_crm_country),
    QueryColumn.new(:address, :sortable => "#{Address.table_name}.full_address", :caption => :label_crm_address),
    QueryColumn.new(:tags),
    QueryColumn.new(:created_on, :sortable => "#{Contact.table_name}.created_on"),
    QueryColumn.new(:updated_on, :sortable => "#{Contact.table_name}.updated_on"),
    QueryColumn.new(:assigned_to, :sortable => lambda {User.fields_for_order_statement}, :groupable => true),
    QueryColumn.new(:author, :sortable => lambda {User.fields_for_order_statement("authors")})
  ]

  scope :visible, lambda {|*args|
    user = args.shift || User.current
    base = Project.allowed_to_condition(user, :view_contacts, *args)
    scope = includes(:project).where("#{table_name}.project_id IS NULL OR (#{base})")

    if user.admin?
      scope.where("#{table_name}.visibility <> ? OR #{table_name}.user_id = ?", VISIBILITY_PRIVATE, user.id)
    elsif user.memberships.any?
      scope.where("#{table_name}.visibility = ?" +
        " OR (#{table_name}.visibility = ? AND #{table_name}.id IN (" +
          "SELECT DISTINCT q.id FROM #{table_name} q" +
          " INNER JOIN #{table_name_prefix}queries_roles#{table_name_suffix} qr on qr.query_id = q.id" +
          " INNER JOIN #{MemberRole.table_name} mr ON mr.role_id = qr.role_id" +
          " INNER JOIN #{Member.table_name} m ON m.id = mr.member_id AND m.user_id = ?" +
          " WHERE q.project_id IS NULL OR q.project_id = m.project_id))" +
        " OR #{table_name}.user_id = ?",
        VISIBILITY_PUBLIC, VISIBILITY_ROLES, user.id, user.id)
    elsif user.logged?
      scope.where("#{table_name}.visibility = ? OR #{table_name}.user_id = ?", VISIBILITY_PUBLIC, user.id)
    else
      scope.where("#{table_name}.visibility = ?", VISIBILITY_PUBLIC)
    end
  }

  def initialize(attributes=nil, *args)
    super attributes
    self.filters = {}
    # self.filters ||= { 'status_id' => {:operator => "o", :values => [""]} }
  end

  def visible?(user=User.current)
    return true if user.admin?
    return false unless project.nil? || user.allowed_to?(:view_contacts, project)
    case visibility
    when VISIBILITY_PUBLIC
      true
    when VISIBILITY_ROLES
      if project
        (user.roles_for_project(project) & roles).any?
      else
        Member.where(:user_id => user.id).joins(:roles).where(:member_roles => {:role_id => roles.map(&:id)}).any?
      end
    else
      user == self.user
    end
  end

  def is_private?
    visibility == VISIBILITY_PRIVATE
  end

  def is_public?
    !is_private?
  end

  def initialize_available_filters
    add_available_filter "tags", :type => :list, :values => Contact.available_tags(project.blank? ? {} : {:project => project.id}).collect{ |t| [t.name, t.name] }, :order => 12
  end

  def available_columns
    return @available_columns if @available_columns
    @available_columns = self.class.available_columns.dup
    @available_columns
  end

  def default_columns_names
    @default_columns_names ||= [:name, :job_title, :company, :phone, :email, :address]
  end

  def sql_for_tags_field(field, operator, value)
    compare   = operator_for('tags').eql?('=') ? 'IN' : 'NOT IN'
    ids_list  = Contact.tagged_with(value).collect{|contact| contact.id }.push(0).join(',')
    "( #{Contact.table_name}.id #{compare} (#{ids_list}) ) "
  end

  def contact_count
    Contact.visible.count(:include => query_includes, :conditions => statement)
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def contact_count_by_group
    r = nil
    if grouped?
      begin
        # Rails3 will raise an (unexpected) RecordNotFound if there's only a nil group value
        r = Contact.visible.count(:joins => joins_for_order_statement(group_by_statement), :group => group_by_statement, :include => query_includes, :conditions => statement)
      rescue ActiveRecord::RecordNotFound
        r = {nil => contact_count}
      end
      c = group_by_column
      if c.is_a?(QueryCustomFieldColumn)
        r = r.keys.inject({}) {|h, k| h[c.custom_field.cast_value(k)] = r[k]; h}
      end
    end
    r
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def results_scope(options={})
    order_option = [group_by_sort_order, options[:order]].flatten.reject(&:blank?)
    scope = Contact.visible
    options[:search].split(' ').collect{ |search_string| scope = scope.live_search(search_string) } unless options[:search].blank?
    scope.includes(query_includes).
      where(statement).
      order(order_option).
      joins(joins_for_order_statement(order_option.join(',')))
  end

  def query_includes
    includes = [:address, :projects]
    includes << :assigned_to if self.filters["assigned_to_id"] || (group_by_column && [:assigned_to].include?(group_by_column.name))
    includes
  end

end
