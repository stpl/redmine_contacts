# encoding: utf-8
#
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

module CrmQueriesHelper

  def contacts_list_style
    list_styles = ['list_excerpt']
    if params[:contacts_list_style].blank?
      list_style = list_styles.include?(session[:contacts_list_style]) ? session[:contacts_list_style] : RedmineContacts.default_list_style
    else
      list_style = list_styles.include?(params[:contacts_list_style]) ? params[:contacts_list_style] : RedmineContacts.default_list_style
    end
    session[:contacts_list_style] = list_style
  end

  def retrieve_crm_query(object_type)
    query_class = Object.const_get("#{object_type.camelcase}Query")
    if !params[:query_id].blank?
      cond = "project_id IS NULL"
      cond << " OR project_id = #{@project.id}" if @project
      @query = query_class.find(params[:query_id], :conditions => cond)
      raise ::Unauthorized unless @query.visible?
      @query.project = @project
      session["#{object_type}_query".to_sym] = {:id => @query.id, :project_id => @query.project_id}
      sort_clear
    elsif api_request? || params[:set_filter] || session["#{object_type}_query".to_sym].nil? || session["#{object_type}_query".to_sym][:project_id] != (@project ? @project.id : nil)
      # Give it a name, required to be valid
      @query = query_class.new(:name => "_")
      @query.project = @project
      @query.build_from_params(params)
      session["#{object_type}_query".to_sym] = {:project_id => @query.project_id, :filters => @query.filters, :group_by => @query.group_by, :column_names => @query.column_names}
    else
      # retrieve from session
      @query = query_class.find_by_id(session["#{object_type}_query".to_sym][:id]) if session["#{object_type}_query".to_sym][:id]
      @query ||= query_class.new(:name => "_", :filters => session["#{object_type}_query".to_sym][:filters], :group_by => session["#{object_type}_query".to_sym][:group_by], :column_names => session["#{object_type}_query".to_sym][:column_names])
      @query.project = @project
    end
  end

end
