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
      @user = env['warden'].user || User.new
    end

    get '/' do
      @query_action = @user.query_action

      @queries = @user.queries_available

      slim :queries
    end

    get '/q/?:q_id?' do
      @query = Query.find(:id => params[:q_id]) || Query.new
      # determine if the form should be editable

      @is_editable = @user.queries_editable.include?(@query)

      puts @is_editable

      slim :query
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

    post '/s/:obj/?:o_id?' do
      # this will be a post method once I get the forms wired up
      o_id = params[:o_id] ? "existing object (with id #{params[:o_id]})" : "new object"
      puts "save the #{o_id} of type: #{params[:obj]}"
      redirect "/#{params[:obj]}/#{params[:o_id]}"
    end

    get '/x/?:q_id?' do
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
@@ query
form method='post' action=url("/s/q/#{@query[:id]}")
  input type='input' name='query[name]' placeholder='meaningful name' readonly=!(@is_editable) value=@query[:name]
  input type='input' name='query[description]' placeholder='useful description' readonly=!(@is_editable) value=@query[:description]
  input type='text' name='query[definition]' placeholder="select 'foo' bar, 'baz' qux" readonly=!(@is_editable) value=@query[:definition]
  input type='submit' disabled=!(@is_editable)
