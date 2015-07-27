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

# dump users
users = JSON.parse(File.read("users.json")).symbolize_keys![:users]
users.each do |user|
  user.symbolize_keys!
  fields = [:username, :password, :lang]
  puts fields.map{|f| %Q{"#{user[f]}"}}.join(",")
end