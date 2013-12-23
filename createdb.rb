require 'sequel'
require 'sqlite3'

DB = Sequel.sqlite('fudq.db')

DB.create_table :users do
  primary_key :id
  String :name, :unique => true
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
  foreign_key :data_source_id, :data_sources
  foreign_key :user_id, :users
  String :name
  String :description
  String :definition
  TrueClass :is_shared
end

DB[:users].insert(
  :name => 'admin',
  :password => 'hushhush')
# :user_id == 1

DB[:users].insert(
  :name => 'test',
  :password => 'secret')
# :user_id == 2

DB[:data_sources].insert(
  :user_id => 1,
  :name => 'fudq',
  :description => 'the database that stores the users, data sources and queries managed by the "system", fudq',
  :type => 'sqlite3',
  :definition => '{"file_location": "./fudq.rb"}',
  :is_shared => 1)
# data_source.id == 1

DB[:queries].insert(
  :data_source_id => 1,
  :user_id => 1,
  :name => 'all fudq data sources',
  :description => 'all attributes of all data sources managed by fudq',
  :definition => 'select * from data_sources',
  :is_shared => 0)
# query.id == 1

DB[:queries].insert(
  :data_source_id => 1,
  :user_id => 1,
  :name => 'all fudq queries',
  :description => 'all attributes of all queries managed by fudq',
  :definition => 'select * from queries',
  :is_shared => 1)
# query.id == 2

DB[:queries].insert(
  :data_source_id => 1,
  :user_id => 2,
  :name => 'test fudq',
  :description => 'intended only for the "test" user, but since the selected data source is shared and owned by admin...well',
  :definition => "select 'my private query!'",
  :is_shared => 0)
# query.id == 3
