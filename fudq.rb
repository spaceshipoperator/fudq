require 'sinatra/base'
require 'rack/flash'
require 'warden'
require 'slim'
require './model.rb'

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

    before do
      public_actions = ['x']
      request_action = request.path_info.split('/')[1]
      env['warden'].authenticate! unless ( request_action.nil? || public_actions.include?(request_action) )
    end

    get '/' do
      user = env['warden'].user || User.new

      @query_action = user.query_action

      @queries = user.queries_available

      slim :queries #'h1 list queries'
      # list all queries shared by other users
      #   select * from queries where ...
      # if we've got a session user:
      #   list queries owned by the current user (each link to edit)
      #   link to new query
    end

    get '/q' do
      # tsk tsk...DB shouldn't be outside the model
      @data_sources = DB[:data_sources]

      slim "h1 new query"
      # list available data source (each link to edit if owned by current user)
      #   one data source must be selected in order to save query
      #   link to new data source
    end

    get '/q/:q_id' do
      slim "h1 view/edit query #{params[:q_id]}"
      # get query from database,
      # if current user is owner then the form is editable,
      # if the query is shared the form is viewable
      # otherwise, whoops
      # link to execute query and delete query
      # post to save
      #   query must belong to the current user before save!
    end

    get '/d' do
      slim "h1 new data source"
    end

    get '/d/:d_id' do
      slim "h1 view/edit data source #{params[:d_id]}"
      # link to disable data source
      # post to save
      #   data source must belong to the current user before save
    end

    #post
    get '/s/:obj/?:o_id?' do
      # this will be a post method once I get the forms wired up
      o_id = params[:o_id] ? "existing object (with id #{params[:o_id]})" : "new object"
      slim "save the #{o_id} of type: #{params[:obj]}"
    end

    get '/x/:q_id' do
      # make sure it's okay we can execute this first y'know
      slim "h1 execute query #{params[:q_id]}"
    end

    get '/admin' do
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
        params['user']['password'])
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
@@ queries
- unless @queries.empty?
  table
    - for query in @queries do
      tr
        td.name
          a href="/#{@query_action}/#{query[:id]}" = query[:name]
        td.description = query[:description]
- else
  p
    | No queries found.  Feel free to create your own.
      Thank you!
