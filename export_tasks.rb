#!/usr/bin/env ruby
require "fileutils"

# used to export the lastest version of tasks

tasks = [["1", "notice"], ["2", "gondola"], ["3", "friend"], ["4", "holiday"]]
tasks.each do |task|
  task_id, task_title = task
  FileUtils.mkdir_p task_title
end

users = File.read("users.lst").split(/\n/)
users.each do |user|
  print "#{user}..."
  tasks.each do |task|
    task_id, task_title = task
    print "#{task_title}..."

    # download latest version
    pdf_url = "http://10.13.1.1/tasks/#{task_id}.pdf?username=#{user}&api_token=4c0a6fe55f3d4aa9c5dbb9a59db7b20e"
    system %Q{wget --content-disposition -P "tmp" "#{pdf_url}" 2> /dev/null}

    # remove if it's rev.0
    filename = Dir.glob("tmp/*").first
    if not filename.include? "rev0"
      File.rename filename, "#{task_title}/#{user}.pdf"
    end

    FileUtils.rm_rf "tmp"
  end
  puts "done"
end
