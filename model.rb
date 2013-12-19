require 'sequel'
require 'sqlite3'

DB = Sequel.sqlite
DB.create_table :users do
  primary_key :id
  String :name
  String :password # don't do this in production!
end

class User < Sequel::Model
  def self.authenticate(name, password)
    user = self.first(name: name)
    user if user && user.password == password
  end
end

User.create(name: 'xyz', password: 'hushhush')
