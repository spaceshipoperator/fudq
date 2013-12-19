require 'sinatra/base'
require 'rack/flash'
require 'warden'
require 'slim'
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

User.create(name: 'abc', password: 'secret')

module App
  class Session < Sinatra::Base
    
    enable :inline_templates
    
    get '/new' do
      slim :new
    end

    post '/' do
      env['warden'].authenticate!
      flash.success = env['warden'].message
      redirect session[:return_to]
    end

    delete '/' do
      env['warden'].raw_session.inspect
      env['warden'].logout
      flash.success = 'Successfully logged out'
      redirect '/'
    end

    post '/unauthenticated' do
      session[:return_to] = env['warden.options'][:attempted_path]
      flash.error = env['warden'].message
      redirect to '/new'
    end
    
    not_found do
      redirect '/' # catch redirects to GET '/session'
    end
  end

  class Main < Sinatra::Base
    
    enable :inline_templates
    
    get '/' do
      slim 'h1 Index'
    end
    
    get '/admin' do
      env['warden'].authenticate!
      slim 'h1 Admin'
    end    
  end
end


builder = Rack::Builder.new do
  Warden::Manager.serialize_into_session{|user| user.id }
  Warden::Manager.serialize_from_session{|id| User[id] }
  
  Warden::Manager.before_failure do |env,opts|
    env['REQUEST_METHOD'] = 'POST'
  end

  Warden::Strategies.add(:password) do
    def valid?
      params['user'] && params['user']['name'] && params['user']['password']
    end

    def authenticate!
      user = User.authenticate(
        params['user']['name'], 
        params['user']['password']
        )
      user.nil? ? fail!('Could not log in') : success!(user, 'Successfully logged in')
    end
  end
  
  use Rack::MethodOverride
  use Rack::Session::Cookie
  use Rack::Flash, accessorize: [:error, :success]
  use Warden::Manager do |config|
    config.scope_defaults :default,
      strategies: [:password], 
      action: 'session/unauthenticated'
    config.failure_app = self
  end

  map '/session' do
    run App::Session
  end

  map '/' do
    run App::Main
  end
end

Rack::Handler::Thin.run builder

__END__
@@ layout
html
head
body
  #flash
    - [:error, :success].each do |name|
      - if flash.has?(name)
        .message class=name
          p = flash[name]
  nav
    ul
      - if env['warden'].authenticated?
        li
          form action='/session' method='post'
            input type='hidden' name='_method' value='delete'
            input type='submit' value='logout'
      - else
        li
          a href='/session/new' login to your account
      li
        a href='/admin' admin
  == yield
@@ new
form method='post' action=url('/')
  input type='input' name='user[name]' placeholder='abc'
  input type='input' name='user[password]' placeholder='secret'
  input type='submit'