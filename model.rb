require 'sequel'
require 'sqlite3'

Sequel::Model.plugin :json_serializer

DB = Sequel.sqlite('fudq.db')

class User < Sequel::Model
  # consider eager loading...
  one_to_many :data_sources
  one_to_many :queries

  alias_method :data_sources_editable, :data_sources
  alias_method :queries_editable, :queries

  def self.authenticate(name, password)
    user = self.first(:name => name)
    user if user && user.password == password
  end

  def data_sources_others_shared
    DataSource.where(:is_shared).exclude(:user_id => self.id).all
  end

  def data_sources_available
    (self.data_sources + self.data_sources_others_shared)
  end

  def queries_others_shared
    Query.where(:is_shared).exclude(:user_id => self.id).all
  end

  def queries_available
    (self.queries + self.queries_others_shared)
  end

  def queries_executable
    self.queries_available.select{|query| self.data_sources_available.include?(query.data_source)}
  end

  # validates_unique [:name]
  # not applicable until there's a new user process...forthcoming
end

class DataSource < Sequel::Model
  many_to_one :user
  one_to_many :queries

  def definition
    JSON.parse(super) unless super.nil?
  end

  def db
    d = self.definition
    db = nil
    case self.type
      when "sqlite"
        db = Sequel.connect("sqlite://#{d['file_location']}")
      when "postgres"
        db = Sequel.connect("postgres://#{d['user']}:#{d['password']}@#{d['host']}/#{d['database']}")
    end

    return db
  end
end

class Query < Sequel::Model
  many_to_one :data_source
  many_to_one :user

  def run
    db = self.data_source.db

    db.fetch(self.definition).all
  end
end
