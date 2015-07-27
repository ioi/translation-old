#!/usr/bin/env ruby

def make_password (len=6)
  chars = "ABCDEFGHJKLMNPQRTUVWXYZ2346789".split(//)
  result = ""; len.times { result += chars.sample }
  result
end

outputs = []

users_path = File.join(File.dirname(__FILE__), "users.json")
lines = File.read(users_path).split(/\n/)
lines.each do |line|
  if line =~ /"password":/
    line = line.gsub('"password":""', %Q{"password":"#{make_password}"})
  end
  outputs << line
end

puts outputs.join("\n")
