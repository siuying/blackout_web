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
  
  def fetch_streets(prefecture, city)
    response = Typhoeus::Request.get("http://ignition.cloudant.com/#{settings.database}/_design/api/_view/streets?group=true&startkey=[%22#{CGI.escape(prefecture)}%22%2C%22#{CGI.escape(city)}%22]&endkey=[%22#{CGI.escape(prefecture)}%22%2C%22#{CGI.escape(city)}%22%2C%22%EF%AB%97%22]")  
    data = JSON(response.body)
    return data["rows"].collect() {|r| r["key"][2] }    
  end
  
  def fetch_blackout_group(p, c, s)
    response = Typhoeus::Request.get "http://ignition.cloudant.com/#{settings.database}/_design/api/_view/blackout?startkey=%22#{CGI.escape(p)}-#{CGI.escape(c)}-#{CGI.escape(s)}%22&endkey=%22#{CGI.escape(p)}-#{CGI.escape(c)}-#{CGI.escape(s)}%EF%AB%97%22"
    data = JSON(response.body)
    data["rows"].first["value"] rescue {}
  end
  
  def fetch_schedule(company, group)
    response = Typhoeus::Request.get "https://ignition.cloudant.com/#{settings.database}/_design/api/_list/time/schedules?startkey=[%222.0%22%2C%22#{company}-#{group}%22]&endkey=[%222.0%22%2C%22#{company}-#{group}%EF%AB%97%22]"
    data = JSON(response.body)
    data.select {|r| r["schedule"] && r["schedule"].length > 0 }.collect do |r|
      r["schedule"].collect do |s|
        fromtime = "#{r["date"]}#{s["time"][0]} JST"
        totime = "#{r["date"]}#{s["time"][1]} JST"
        group = r["key"][1].split("-")[1] rescue nil
        
        {
          "group" => group,
          "from" => DateTime.strptime(fromtime, '%Y%m%d%H%M %Z'),
          "to" => DateTime.strptime(totime, '%Y%m%d%H%M %Z'),
          "message" => s["message"]
        }
      end
    end
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
  @streets = fetch_streets(@prefecture, @city)

  erb :street
end

get "/:prefecture/:city/:street" do
  halt 404 if params[:prefecture].nil? || params[:city].nil? || params[:city].nil?
    
  @prefecture = params[:prefecture]
  @city = params[:city]  
  @street = params[:street]  
  @group = fetch_blackout_group(@prefecture, @city, @street)
  halt 404 if @group.nil?
  
  @schedules = @group["group"].collect {|g| fetch_schedule(@group["company"], g) }.flatten.sort {|x,y| x["from"] <=> y["from"] }
  
  @company = "東京電力" if @group["company"] == "tepco"
  erb :blackout
end