class AddIsActiveToContact < ActiveRecord::Migration
  def change
  	add_column :contacts, :is_active, :boolean, default: false
  end
end
