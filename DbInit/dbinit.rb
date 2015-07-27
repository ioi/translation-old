#!/usr/bin/env ruby
require "json"
require "fileutils"

require "redis"
require "redis-namespace"

# monkey patch on Ruby Hash
class Hash
  def symbolize_keys!
    # ref. http://stackoverflow.com/questions/8379596
    self.keys.each do |k|
      ks = k.respond_to?(:to_sym) ? k.to_sym : k
      self[ks] = self.delete k # Preserve order even when k == ks
      self[ks].symbolize_keys! if self[ks].kind_of? Hash
    end
    self
  end
end

# database connection
$redis_conn = Redis.new(:thread_safe => true)
$redis = Redis::Namespace.new(:linguist, :redis => $redis_conn)

# select & flush database
$redis.select(0)
$redis.flushdb

# remove tmp
tmpdir_path = File.join(File.dirname(__FILE__), "..", "tmp")
FileUtils.rm_rf(Dir.glob(File.join(tmpdir_path, "*")))

# create global tasks
tasks = JSON.parse(File.read("tasks.json")).map(&:symbolize_keys!)
tasks.each do |task_meta|
  text_path = File.join(File.dirname(__FILE__), task_meta[:filename])
  text = File.read(text_path).force_encoding(Encoding::UTF_8)
  task = {
    :id => task_meta[:id],
    :title => task_meta[:title],
    :initial_text => text
  }
  redis_key = "tasks:#{task[:id]}"
  task.each do |field, value|
    $redis.hset(redis_key, field, value)
  end
end

# country: ISO Country Codes (e.g. TWN)
# lang: IETF Language Tag (e.g. zh-TW)

# create users
users_data = JSON.parse(File.read("users.json")).symbolize_keys!
default_user = users_data[:default_user].symbolize_keys!
users = users_data[:users].map(&:symbolize_keys!)
users.each do |user_data|
  user = default_user.clone
  user_data.each do |field, value|
    user[field] = value
  end
  user[:username].downcase!

  redis_key = "users:#{user[:username]}"
  user.each do |field, value|
    $redis.hset(redis_key, field, value)
  end

  # initialize tasks
  tasks_keys = $redis.keys("tasks:*").select{|k| k.count(":") == 1}
  tasks_keys.each do |task_key|
    task_id = task_key.split(":")[1]
    task_text = $redis.hget(task_key, :initial_text)
    redis_key = "users:#{user[:username]}:tasks:#{task_id}:revisions"
    $redis.rpush(redis_key, {
      :text => task_text,
      :created_at => Time.now.strftime("%s.%L"),
      :created_from => "127.0.0.1"
    }.to_json)
  end
end

# initialize ISC releases
tasks_keys = $redis.keys("tasks:*").select{|k| k.count(":") == 1}
tasks_keys.each do |task_key|
task_id = task_key.split(":")[1]
redis_key = "users:isc:tasks:#{task_id}:releases"
$redis.rpush(redis_key, {
  :revision_num => 0,
  :note => 'initial commit',
  :created_at => Time.now.strftime("%s.%L"),
  :created_from => '127.0.0.1'
}.to_json)
end