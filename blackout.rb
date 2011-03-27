require "bundler"
Bundler.require(:default)

require "sinatra"
require "rack/cache"
require 'memcached'
require 'cgi'
  
# $cache = Memcached.new
# use Rack::Cache, :verbose => true, :metastore => $cache, :entitystore => $cache

configure do
  set :database, 'blackout-dev'
end

set :views, File.dirname(__FILE__) + '/views'
set :public, File.dirname(__FILE__) + '/public'

helpers do
  def fetch_prefectures
    response = Typhoeus::Request.get("http://ignition.cloudant.com/#{settings.database}/_design/api/_view/prefectures?group=true")  
    data = JSON(response.body)
    return data["rows"].collect() {|r| r["key"]}    
  end
  
  def fetch_cities(prefecture)
    response = Typhoeus::Request.get("http://ignition.cloudant.com/#{settings.database}/_design/api/_view/cities?group=true&startkey=[%22#{CGI.escape(prefecture)}%22]&endkey=[%22#{CGI.escape(prefecture)}%22%2C%22%EF%AB%97%22]")  
    data = JSON(response.body)
    return data["rows"].collect() {|r| r["key"][1] }    
  end
  
  def fetch_blackout_group(p, c)
    response = Typhoeus::Request.get "http://ignition.cloudant.com/#{settings.database}/_design/api/_view/blackout?startkey=%22#{CGI.escape(p)}-#{CGI.escape(c)}%22&endkey=%22#{CGI.escape(p)}-#{CGI.escape(c)}%EF%AB%97%22"
    data = JSON(response.body)
    data["rows"].first["value"] rescue {}
  end
end

get "/" do
  @prefectures = fetch_prefectures
  erb :prefecture
end

get "/:prefecture" do
  halt 404 if params[:prefecture].nil?
  
  @prefecture = params[:prefecture]
  @cities = fetch_cities(params[:prefecture])  
  erb :city
end

get "/:prefecture/:city" do
  halt 404 if params[:prefecture].nil? || params[:city].nil?
    
  @prefecture = params[:prefecture]
  @city = params[:city]  
  @group = fetch_blackout_group(@prefecture, @city)
  halt 404 if @group.nil?
  
  @company = "東京電力" if @group["company"] == "tepco"
  erb :blackout
end