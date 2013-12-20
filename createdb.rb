require 'sequel'
require 'sqlite3'

DB = Sequel.sqlite('fudq.db')

DB.create_table :users do
  primary_key :id
  String :name
  String :password # don't do this in production!
end

DB.create_table :data_sources do
  primary_key :id
  foreign_key :user_id, :users
  String :name
  String :description
  String :type
  String :definition
  TrueClass :is_shared
end

DB.create_table :queries do
  primary_key :id
  foreign_key :data_source_id
  String :name
  String :description
  String :definition
  TrueClass :is_shared

DB[:users].insert(name: 'admin', password: 'hushhush')
