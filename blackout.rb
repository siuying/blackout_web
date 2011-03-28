require 'rubygems'

require "bundler"
Bundler.require(:default)

require "sinatra"
require "rack/cache"
require 'memcached'
require 'cgi'

require 'active_support'
require 'active_support/core_ext/time/zones'
require 'active_support/time_with_zone'

Time.zone = "Japan"

# $cache = Memcached.new
# use Rack::Cache, :verbose => true, :metastore => $cache, :entitystore => $cache

configure do
  set :database, 'blackout'
end

set :views, File.dirname(__FILE__) + '/views'
set :public, File.dirname(__FILE__) + '/public'


helpers do
  def fetch_prefectures
    response = Typhoeus::Request.get("http://ignition.cloudant.com/#{settings.database}/_design/api/_view/prefectures?group=true", :cache_timeout => 60)  
    data = JSON(response.body)
    return data["rows"].collect() {|r| r["key"]}    
  end
  
  def fetch_cities(prefecture)
    response = Typhoeus::Request.get("http://ignition.cloudant.com/#{settings.database}/_design/api/_view/cities?group=true&startkey=[%22#{CGI.escape(prefecture)}%22]&endkey=[%22#{CGI.escape(prefecture)}%22%2C%22%EF%AB%97%22]", :cache_timeout => 60)  
    data = JSON(response.body)
    return data["rows"].collect() {|r| r["key"][1] }    
  end
  
  def fetch_streets(prefecture, city)
    response = Typhoeus::Request.get("http://ignition.cloudant.com/#{settings.database}/_design/api/_view/streets?group=true&startkey=[%22#{CGI.escape(prefecture)}%22%2C%22#{CGI.escape(city)}%22]&endkey=[%22#{CGI.escape(prefecture)}%22%2C%22#{CGI.escape(city)}%22%2C%22%EF%AB%97%22]", :cache_timeout => 60)  
    data = JSON(response.body)
    return data["rows"].collect() {|r| r["key"][2] }    
  end
  
  def fetch_blackout_group(p, c, s)
    response = Typhoeus::Request.get("http://ignition.cloudant.com/#{settings.database}/_design/api/_view/blackout?startkey=%22#{CGI.escape(p)}-#{CGI.escape(c)}-#{CGI.escape(s)}%22&endkey=%22#{CGI.escape(p)}-#{CGI.escape(c)}-#{CGI.escape(s)}%EF%AB%97%22", :cache_timeout => 60)
    data = JSON(response.body)
    data["rows"].first["value"] rescue {}
  end
  
  def fetch_schedule(company, group)
    response = Typhoeus::Request.get("https://ignition.cloudant.com/#{settings.database}/_design/api/_list/time/schedules?startkey=[%222.0%22%2C%22#{company}-#{group}%22]&endkey=[%222.0%22%2C%22#{company}-#{group}%EF%AB%97%22]", :cache_timeout => 60)
    data = JSON(response.body)

    data.select {|r| r["schedule"] && r["schedule"].length > 0 }.collect do |r|
      r["schedule"].collect do |s|
        fromtime = "#{r["date"]} #{s["time"][0]} +0900"
        totime = "#{r["date"]} #{s["time"][1]} +0900"
        group = r["key"][1].split("-")[1] rescue nil
        from = Time.parse(fromtime)
        to = Time.parse(totime)

        {
          "group" => group,
          "from" => Time.zone.parse(fromtime),
          "to" => Time.zone.parse(totime),
          "message" => s["message"],
          "from_s" => fromtime,
          "to_s" => totime
        }
      end
    end
  end
  
  def distance_of_time_in_words(from_time, to_time = 0)
    from_time = from_time.to_time if from_time.respond_to?(:to_time)
    to_time = to_time.to_time if to_time.respond_to?(:to_time)
    from_time = from_time.time if from_time.respond_to?(:time)
    to_time = to_time.time if to_time.respond_to?(:time)
    
    distance_in_seconds = ((to_time - from_time).abs).ceil
    distance_in_minutes = ((to_time - from_time).abs/60).ceil % 60
    distance_in_hours = ((to_time - from_time).abs/3600).floor % 24
    distance_in_days = ((to_time - from_time).abs/(3600*24)).floor
            
    min_words = (distance_in_minutes == 0) ? "" : "#{distance_in_minutes}分"
    hour_words = (distance_in_hours == 0) ? "" : "#{distance_in_hours}時"
    day_words = (distance_in_days == 0) ? "" : "#{distance_in_days}日"
    
    return "#{day_words}#{hour_words}#{min_words}"
  end
end

get "/" do
  cache_control :public, :max_age => 3600
  @prefectures = fetch_prefectures
  erb :prefecture
end

get "/:prefecture" do
  cache_control :public, :max_age => 3600
  halt 404 if params[:prefecture].nil?
  
  @prefecture = params[:prefecture]
  @cities = fetch_cities(params[:prefecture])  
  erb :city
end

get "/:prefecture/:city" do
  cache_control :public, :max_age => 3600
  halt 404 if params[:prefecture].nil? || params[:city].nil?
    
  @prefecture = params[:prefecture]
  @city = params[:city]  
  @streets = fetch_streets(@prefecture, @city)

  erb :street
end

get "/:prefecture/:city/:street" do
  cache_control :public, :max_age => 60
  
  halt 404 if params[:prefecture].nil? || params[:city].nil? || params[:city].nil?
    
  @prefecture = params[:prefecture]
  @city = params[:city]  
  @street = params[:street]  
  @group = fetch_blackout_group(@prefecture, @city, @street)
  halt 404 if @group.nil?
  
  @orig_schedules = @group["group"].collect { |g| fetch_schedule(@group["company"], g) } rescue []
  @schedules = @orig_schedules.flatten.select {|s| s["from"] > Time.now }
  @next_schedule = @schedules.first

  if @next_schedule
    if @next_schedule["from"] >= Time.now && @next_schedule["to"] < Time.now
      @next_schedule_title = "停電予定終了まで"
      @next_schedule_time = distance_of_time_in_words(Time.now, @next_schedule["to"])
    else
      @next_schedule_title = "計画停電まで"
      @next_schedule_time = distance_of_time_in_words(@next_schedule["from"], Time.now)
    end
  end
  
  @company = "東京電力" if @group["company"] == "tepco"
  erb :blackout
end