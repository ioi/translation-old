require File.join(File.dirname(__FILE__), "app")

run Rack::URLMap.new \
  "/" => Linguist::App.new,
  "/notifications" => LinguistNotification::App.new,
  "/assets" => Rack::Directory.new("public")
