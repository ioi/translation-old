@dir = File.dirname(__FILE__)

preload_app true
worker_processes 128
working_directory @dir
listen "127.0.0.1:8081"

pid "#{@dir}/unicorn/pid"
stderr_path "#{@dir}/unicorn/stderr"
stdout_path "#{@dir}/unicorn/stdout"
