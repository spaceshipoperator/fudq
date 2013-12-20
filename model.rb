require 'sequel'
require 'sqlite3'

DB = Sequel.sqlite('fudq.db')

class User < Sequel::Model
  def self.authenticate(name, password)
    user = self.first(:name => name)
    user if user && user.password == password
  end
end
