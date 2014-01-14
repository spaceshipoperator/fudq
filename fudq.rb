require 'sinatra/base'
require 'sinatra/json'
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
    helpers Sinatra::JSON

    enable :inline_templates

    before do
      public_actions = ['x']
      request_action = request.path_info.split('/')[1]
      env['warden'].authenticate! unless ( request_action.nil? || public_actions.include?(request_action) )
      @user = env['warden'].user || User.new
    end

    get '/' do
      @data_sources = @user.data_sources_available

      @queries = @user.queries_available

      slim :home
    end

    get '/q/?:q_id?' do
      @query = Query.find(:id => params[:q_id]) || Query.new

      @is_editable = @query.id.nil? || @user.queries_editable.include?(@query)

      slim :query
    end

    get '/d/?:d_id?' do
      @data_source = DataSource.find(:id => params[:d_id]) || DataSource.new

      @is_editable = @data_source.id.nil? || @user.data_sources_editable.include?(@data_source)

      slim :data_source
    end

    post '/:obj/?:o_id?' do
      case params[:obj]
        when "q"
          o_id = save_query(params[:o_id], params[:query])
          flash.success = 'query saved!' unless o_id.nil?
        when "d"
          o_id = save_data_source(params[:o_id], params[:data_source])
          flash.success = 'data source saved!' unless o_id.nil?
        else
          puts "don't know how to save such a thing"
      end

      redirect "/#{params[:obj]}/#{o_id}"
    end

    def save_query(query_id, query_attributes)
      query = query_id.nil? ? Query.new : Query.find(:id => query_id)

      if (query.id.nil? || @user.queries_editable.include?(query)) then
        query.user_id = @user.id
        query.data_source_id = query_attributes[:data_source_id]
        query.name = query_attributes[:name]
        query.description = query_attributes[:description]
        query.definition = query_attributes[:definition]
        query.is_shared = query_attributes[:is_shared].nil? ? 0 : 1
      end

      saved_query = query.save

      return saved_query.id
    end

    def save_data_source(data_source_id, data_source_attributes)
      data_source = data_source_id.nil? ? DataSource.new : DataSource.find(:id => data_source_id)

      if (data_source.id.nil? || @user.data_sources_editable.include?(data_source)) then
        data_source.user_id = @user.id
        data_source.name = data_source_attributes[:name]
        data_source.description = data_source_attributes[:description]
        data_source.definition = data_source_attributes[:definition]
        data_source.is_shared = data_source_attributes[:is_shared].nil? ? 0 : 1
      end

      saved_data_source = data_source.save

      return saved_data_source.id
    end

    delete '/:obj/:o_id' do
      case params[:obj]
        when "q"
          o_id = delete_query(params[:o_id])
          flash.success = "deleted query #{o_id}!" unless o_id.nil?
        else
          puts "don't know how to delete such a thing"
      end

      redirect "/"
    end

    def delete_query(query_id)
      query = Query.find(:id => query_id) || Query.new
      deleted_query_id = query.id

      if @user.queries_editable.include?(query) then
        query.delete
      end

      return deleted_query_id
    end

    get '/x/:q_id' do
      query = Query.find(:id => params[:q_id]) || Query.new

      results = ""

      if @user.queries_executable.include?(query) then
        results = query.run
      end

      json results
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
  script src="http://code.jquery.com/jquery-2.0.3.min.js" type="text/javascript" charset="utf-8"
  script src="/ace-builds/src-noconflict/ace.js" type="text/javascript" charset="utf-8"
body
  #flash
    - [:error, :success].each do |name|
      - if flash.has?(name)
        .message class=name
          p = flash[name]
  nav
    h3 ="welcome, #{@user.nil? ? 'please login' : @user.name}"
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
        a href='/' home
  br
  == yield
@@ new
form method='post' action=url('/')
  input type='input' name='user[name]' placeholder='abc'
  input type='input' name='user[password]' placeholder='secret'
  input type='submit'
@@ home
- unless (@user.id.nil? || @data_sources.empty?)
  a href="/d" ="new data source"
  hr
  table
    - for data_source in @data_sources do
      tr
        td.name
          a href="/d/#{data_source[:id]}" = data_source[:name]
        td.description = data_source[:description]
  br
- unless @queries.empty?
  - unless @user.id.nil?
    a href="/q" ="new query"
    hr
  table
    - for query in @queries do
      tr
        td.name
          a href="/q/#{query[:id]}" = query[:name]
        td.description = query[:description]
        td.run
          - if @user.queries_executable.include?(query)
            a href="/x/#{query[:id]}" ="run"
  br
- else
  p
    | No queries found.  Feel free to create your own.
      Thank you!
@@ query
form id='saveQuery' method='post' action=url("/q/#{@query.id}")
  p ="query name:"
  input type='text' name='query[name]' placeholder='meaningful name' readonly=!(@is_editable) value=@query.name
  p ="data source:"
  select name='query[data_source_id]' readonly=!(@is_editable)
    - for data_source in @user.data_sources_available
      - if (data_source.id == @query.data_source_id)
        option value=data_source.id selected="" =data_source.name
      - else
        option value=data_source.id =data_source.name
  p ="description:"
  textarea name='query[description]' placeholder='useful description' readonly=!(@is_editable) =@query.description
  p ="definition:"
  input id='queryDefinition' type='hidden' name='query[definition]' value=@query.definition
  #queryEditor style="height: 200px; width: 600px"
    =@query.definition
  p
  label
    - if @query.is_shared
      input type='checkbox' name='query[is_shared]' readonly=!(@is_editable) checked="" value=1
    - else
      input type='checkbox' name='query[is_shared]' readonly=!(@is_editable) value=1
    ="  share this query with others"
  br
  input type='submit' disabled=!(@is_editable)
- if (@user.queries_editable.include?(@query))
  form id='deleteQuery' method='post' action=url("/q/#{@query.id}")
    input type='hidden' name='_method' value='delete'
    input type='submit' value='delete'
javascript:
  var editor = ace.edit("queryEditor");
  editor.setTheme("ace/theme/chrome");
  editor.getSession().setMode("ace/mode/sql");
  $("#saveQuery").submit(function() {
    $("#queryDefinition").val(editor.getValue());
  });
@@ data_source
form method='post' action=url("/d/#{@data_source.id}")
  p ="data source name:"
  input type='text' name='data_source[name]' placeholder='meaningful name' readonly=!(@is_editable) value=@data_source.name
  p ="data source type:"
  input type='text' name='data_source[type]' placeholder='sqlite' readonly=!(@is_editable) value=@data_source.type
  p ="description:"
  textarea name='data_source[description]' placeholder='useful description' readonly=!(@is_editable) =@data_source.description
  p ="definition:"
  textarea name='data_source[definition]' placeholder='{"file_location": "./fudq.db"}' readonly=!(@is_editable) =@data_source.definition
  p
  label
    - if @data_source.is_shared
      input type='checkbox' name='data_source[is_shared]' readonly=!(@is_editable) checked="" value=1
    - else
      input type='checkbox' name='data_source[is_shared]' readonly=!(@is_editable) value=1
    ="  share this data source with others"
  br
  input type='submit' disabled=!(@is_editable) value='save'
- if (@user.data_sources_editable.include?(@data_source))
  form method='post' action=url("/d/#{@data_source.id}")
    input type='hidden' name='_method' value='delete'
    input type='submit' value='delete'
