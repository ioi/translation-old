# encoding: utf-8
Encoding.default_internal = "utf-8"
Encoding.default_external = "utf-8"

# built-ins
require "json"
require "securerandom"
require "fileutils"
require "open3"

# dependencies
require "sinatra"
require "sinatra/base"
require "sinatra/flash"
require "sinatra/content_for"
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

# load config
require "yaml"
config_path = File.join(File.dirname(__FILE__), "config.yml")
$config = YAML.load_file(config_path).symbolize_keys!

# major server
module Linguist
  class App < Sinatra::Base
    redis_connection = Redis.new(:thread_safe => true)
    @@redis = Redis::Namespace.new(:linguist, :redis => redis_connection)
    @@api_token = $config[:api_token]

    use Rack::MethodOverride
    use Rack::Session::Cookie,
      :key => "linguist.sessions",
      :path => "/",
      :expire_after => 86400, # in second
      :secret => $config[:cookie_secret]
    register Sinatra::Flash

    helpers Sinatra::ContentFor
    helpers do
      def render(*args)
        # Rails-style partial, ref. http://steve.dynedge.co.uk/2010/04/14/render-rails-style-partials-in-sinatra/
        if args.first.is_a?(Hash) && args.first.keys.include?(:partial)
          return erb "_#{args.first[:partial]}".to_sym, :layout => false
        else
          super
        end
      end

      def get_user (username)
        username.downcase!
        redis_key = "users:#{username}"
        user = @@redis.hgetall(redis_key).symbolize_keys!
        return nil if user.empty?

        user.merge({:username => username})
        return user
      end

      def login_required!
        session[:username] = "api" if params[:api_token] == @@api_token
        @user = get_user(session[:username])
        if @user.nil?
          flash[:error] = "Please log in first."
          redirect to("/")
        end
      end

      # permission_required! :admin, :staff
      def permission_required! (*roles)
        login_required!
        roles = (roles.empty?) ? [:admin].map(&:to_s) : roles.map(&:to_s)
        unless roles.map{|p| p.to_s}.include? @user[:role].downcase
          flash[:error] = "Permission denied."
          redirect to("/")
        end
      end

      def tmpfile_path (prefix="", ext="")
        tmp_rootdir = File.join(File.dirname(__FILE__), "tmp")
        tmp_dir = File.join(tmp_rootdir, prefix)
        FileUtils.mkdir_p(tmp_dir)

        rand_str = SecureRandom.hex(4)
        File.join(tmp_dir, "#{prefix}#{rand_str}#{ext}")
      end

      def get_pdf_path (username, task_id, revision_num)
        tmp_rootdir = File.join(File.dirname(__FILE__), "tmp")
        tmp_dir = File.join(tmp_rootdir, username)
        FileUtils.mkdir_p(tmp_dir)

        File.join(tmp_dir, "#{username}_task#{task_id}_rev#{revision_num}.pdf")
      end

      def send_notification (from, to, text)
        redis_key = "notifications"
        @@redis.rpush(redis_key, {
          :from => from,
          :to => to.to_s,
          :text => text,
          :created_at => Time.now.strftime("%s.%L")
        }.to_json)
      end
    end

    # Index, Log-in/out
    # ==========================================================================
    get "/" do
      if session[:username]
          login_required!
          redirect to("/tasks")
      else
          erb :login
      end
    end

    post "/login" do
      username = params[:username].downcase
      password = params[:password]
      stored_password = @@redis.hget("users:#{username}", :password)
      if stored_password == password and not password.empty?
        session[:username] = username
      else
        flash[:error] = "Authentication failed."
      end
      redirect to("/")
    end

    get "/logout" do
      session.delete :username
      redirect to("/")
    end

    # admin backdoor -- /su?username=dannvix
    get "/su/:username" do |username|
      permission_required!
      username.downcase!
      if not @@redis.keys("users:#{username}").empty?
        session[:username] = username.downcase
        flash[:info] = "Impersonate to #{username} successfully."
      else
        flash[:error] = "No such user #{username}"
      end

      redirect to("/")
    end


    # User settings
    # ==========================================================================
    get "/settings" do
      login_required!
      erb :settings
    end

    put "/settings" do
      login_required!

      redis_key = "users:#{@user[:username]}"
      fields = [:direction, :font, :plaintext_editor]
      fields.each do |field|
        @@redis.hset(redis_key, field, params[field]) if params[field]
      end

      flash[:info] = "Settings updatd successfully"
      redirect to("/settings")
    end

    # Get ISC tasks
    # ==========================================================================
    get "/ISC/tasks/:task_id/releases" do |task_id|
      login_required!
      redis_key = "tasks:#{task_id}"
      @task = @@redis.hgetall(redis_key).symbolize_keys!

      redis_key = "users:isc:tasks:#{task_id}:releases"
      @releases = @@redis.lrange(redis_key, 0, -1).map do |item|
        JSON.parse(item).symbolize_keys!
      end
      @releases.sort! {|a,b| a[:created_at] <=> b[:created_at] }

      erb :isc_releases
    end

    get "/ISC/tasks/:task_id/diff" do |task_id|
      login_required!
      redis_key = "tasks:#{task_id}"
      @task = @@redis.hgetall(redis_key).symbolize_keys!

      redis_key = "users:isc:tasks:#{task_id}:releases"
      @releases = @@redis.lrange(redis_key, 0, -1)

      index = 0
      @releases = @releases.map do |item|
        item = JSON.parse(item).symbolize_keys!
        revision_key = "users:isc:tasks:#{task_id}:revisions"
        revision = JSON.parse(@@redis.lindex(revision_key, item[:revision_num])).symbolize_keys!
        item.merge!({:text => revision[:text]})
        item.merge!({:num => index})
        index += 1
        item
      end
      @releases.sort! {|a,b| a[:created_at] <=> b[:created_at] }
      erb :isc_diff
    end

    get "/ISC/tasks/:task_id.md" do |task_id|
      login_required!
      redis_key = "users:isc:tasks:#{task_id}:revisions"

      # last revision or specified
      if params[:revision]
        revision_num = params[:revision].to_i
      else
        revision_num = @@redis.llen(redis_key) - 1 # last revision
      end

      revision_json = @@redis.lindex(redis_key, revision_num)
      @revision = JSON.parse(revision_json).symbolize_keys!

      content_type "text/plain", :charset => "utf-8"
      return @revision[:text]
    end

    get "/ISC/tasks/:task_id.html" do |task_id|
      login_required!

      @owner = get_user("isc")
      redis_key = "users:isc:tasks:#{task_id}:revisions"

      # last revision or specifed
      if params[:revision]
        revision_num = params[:revision].to_i
      else
        revision_num = @@redis.llen(redis_key) - 1 # last revision
      end

      revision_json = @@redis.lindex(redis_key, revision_num)
      @task = JSON.parse(revision_json).symbolize_keys!

      redis_key = "tasks:#{task_id}"
      task = @@redis.hgetall(redis_key).symbolize_keys!
      @task.merge!(task)

      erb :tasks_preview
    end

    get "/ISC/tasks/:task_id.pdf" do |task_id|
      login_required!

      preview_url = "#{request.scheme}://127.0.0.1:#{request.port}/ISC/tasks/#{task_id}.html?api_token=#{@@api_token}"
      @owner = get_user("isc")

      if params[:revision]
        revision_num = params[:revision].to_i
        preview_url = "#{preview_url}&revision=#{revision_num}"
      else
        redis_key = "users:isc:tasks:#{task_id}:revisions"
        revision_num = @@redis.llen(redis_key) - 1
      end

      # cached PDF generation
      pdf_path = get_pdf_path(@owner[:username], task_id, revision_num)
      if not File.exist? pdf_path
        html2pdf_path = File.join(File.dirname(__FILE__), "bin", "html2pdf.js")
        phantomjs_cmd = "phantomjs --ignore-ssl-errors=yes '#{html2pdf_path}' '#{preview_url}' '#{pdf_path}'"
        output, status = Open3.capture2(phantomjs_cmd, :stdin_data => nil)
      end

      sendfile_options = {
        :filename => "task-#{task_id}_#{@owner[:lang]}_rev#{revision_num}.pdf",
        :disposition => :attachment
      }
      send_file pdf_path, sendfile_options
    end

    # User tasks
    # ==========================================================================
    get "/tasks/:task_id/revisions" do |task_id|
      login_required!

      redis_key = "tasks:#{task_id}"
      @task = @@redis.hgetall(redis_key).symbolize_keys!

      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:revisions"
      @revisions = @@redis.lrange(redis_key, -1024, -1).map do |item|
        JSON.parse(item).symbolize_keys!
      end

      last_revision_num = @@redis.llen(redis_key) - 1
      tmp = @revisions.length - 1
      @revisions = @revisions.map do |r|
        r.merge!({:num => (last_revision_num - tmp)})
        tmp -= 1
        r
      end

      erb :tasks_revisions
    end

    post "/tasks/:task_id/revisions" do |task_id|
      login_required!
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:revisions"
      @@redis.rpush(redis_key, {
        :text => params[:text],
        :created_at => Time.now.strftime("%s.%L"),
        :created_from => request.ip
      }.to_json)

      last_revision_num = @@redis.llen(redis_key) - 1
      last_revision_num.to_s
    end

    # get "/tasks/:task_id/releases" do |task_id|
    #   login_required!
    #   redis_key = "users:#{@user[:username]}:tasks:#{task_id}:releases"
    #   @releases = @@redis.lrange(redis_key, 0, -1).map do |item|
    #     JSON.parse(item).symbolize_keys!
    #   end
    #   erb :tasks_releases
    # end

    post "/tasks/:tasks_id/releases" do |task_id|
      login_required!
      release_note = params[:note]

      # get last revision
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:revisions"
      last_revision_num = @@redis.llen(redis_key) - 1

      # create release
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:releases"
      @@redis.rpush(redis_key, {
        :revision_num => last_revision_num,
        :note => release_note,
        :created_at => Time.now.strftime("%s.%L"),
        :created_from => request.ip
      }.to_json)

      last_release_ver = @@redis.llen(redis_key) - 1

      # ISC specified -- broadcast task updates
      if @user[:username] == "isc"
        redis_key = "tasks:#{task_id}"
        task = @@redis.hgetall(redis_key).symbolize_keys!

        text = %Q{ISC updates "#{task[:title]}" to version #{last_release_ver+1}: #{release_note}.}
        send_notification(@user[:username], ".*", text)
      else
        text = %Q{#{@user[:username]} releases version #{last_release_ver+1} of task #{task_id}.}
        send_notification(@user[:username], "admin", text)
      end

      return last_release_ver.to_s
      # redirect to("/tasks/#{task_id}/releases")
    end

    post "/tasks/:task_id/edit_heartbeat" do |task_id|
      login_required!

      # check if frozen
      redis_key = "users:#{@user[:uesrname]}:tasks:#{task_id}:frozen"
      if @@redis.get(redis_key)
        return "frozen"
      end

      # acquire edit lock (with TTL), client should poll this every 7.5 seconds
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:editing"
      @@redis.set(redis_key, "yes")
      @@redis.expire(redis_key, 10) # in seconds, will reset existing TTL
    end

    get "/tasks/:task_id/edit" do |task_id|
      login_required!
      # global task metadata
      redis_key = "tasks:#{task_id}"
      @task = @@redis.hgetall(redis_key).symbolize_keys!

      # check if frozen
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:frozen"
      if @@redis.get(redis_key)
        flash[:error] = %Q{The task "#{@task[:title]}" is frozen. Please ask the staff.}
        redirect to("/tasks")
      end

      # check edit lock
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:editing"
      if @@redis.get(redis_key)
        flash[:warning] = %Q{Somebody is editing the task "#{@task[:title]}" currently. Try again later.}
        redirect to("/tasks")
      end

      # acquire edit lock (with TTL), client should poll this every 7.5 seconds
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:editing"
      @@redis.set(redis_key, "yes")
      @@redis.expire(redis_key, 10) # in seconds, will reset existing TTL

      # last revision
      redis_key = "users:#{@user[:username]}:tasks:#{task_id}:revisions"
      @last_revision_num = @@redis.llen(redis_key) - 1
      last_revision_json = @@redis.lindex(redis_key, @last_revision_num)
      last_revision = JSON.parse(last_revision_json).symbolize_keys!
      @task.merge!(last_revision)

      erb :tasks_edit
    end

    get "/tasks/:task_id.md" do |task_id|
      login_required!

      # impersonate for PDF backend access
      if params[:username]
        permission_required! :admin, :staff
        username = params[:username].downcase
        @owner = get_user(username)
      else
        username = session[:username]
        @owner = @user
      end
      redis_key = "users:#{username}:tasks:#{task_id}:revisions"

      # last revision or specified
      if params[:revision]
        revision_num = params[:revision].to_i
      else
        revision_num = @@redis.llen(redis_key) - 1 # last revision
      end

      revision_json = @@redis.lindex(redis_key, revision_num)
      @revision = JSON.parse(revision_json).symbolize_keys!

      content_type "text/plain", :charset => "utf-8"
      return @revision[:text]
    end

    get "/tasks/:task_id.html" do |task_id|
      login_required!

      # impersonate for PDF backend access
      if params[:username]
        permission_required! :admin, :staff
        username = params[:username].downcase
        @owner = get_user(username)
      else
        username = session[:username]
        @owner = @user
      end
      redis_key = "users:#{username}:tasks:#{task_id}:revisions"

      # last revision or specifed
      if params[:revision]
        revision_num = params[:revision].to_i
      else
        revision_num = @@redis.llen(redis_key) - 1 # last revision
      end

      revision_json = @@redis.lindex(redis_key, revision_num)
      @task = JSON.parse(revision_json).symbolize_keys!

      redis_key = "tasks:#{task_id}"
      task = @@redis.hgetall(redis_key).symbolize_keys!
      @task.merge!(task)

      erb :tasks_preview
    end

    get "/tasks/:task_id.pdf" do |task_id|
      login_required!
      preview_url = "#{request.scheme}://127.0.0.1:#{request.port}/tasks/#{task_id}.html?api_token=#{@@api_token}"

      # impersonate for PDF backend access
      if params[:username]
        permission_required! :admin, :staff
        username = params[:username]
        @owner = get_user(username)
      end
      @owner ||= @user
      preview_url = "#{preview_url}&username=#{@owner[:username]}"

      if params[:revision]
        revision_num = params[:revision].to_i
        preview_url = "#{preview_url}&revision=#{revision_num}"
      else
        redis_key = "users:#{@owner[:username]}:tasks:#{task_id}:revisions"
        revision_num = @@redis.llen(redis_key) - 1
      end

      # cached PDF generation
      pdf_path = get_pdf_path(@owner[:username], task_id, revision_num)
      if not File.exist? pdf_path
        html2pdf_path = File.join(File.dirname(__FILE__), "bin", "html2pdf.js")
        phantomjs_cmd = "phantomjs --ignore-ssl-errors=yes '#{html2pdf_path}' '#{preview_url}' '#{pdf_path}'"
        output, status = Open3.capture2(phantomjs_cmd, :stdin_data => nil)
      end

      sendfile_options = {
        :filename => "task-#{task_id}_#{@owner[:lang]}_rev#{revision_num}.pdf",
        :disposition => :attachment
      }
      send_file pdf_path, sendfile_options
    end

    get "/tasks" do
      login_required!

      redis_keys = @@redis.keys("tasks:*")
      @tasks = redis_keys.map do |redis_key|
        task = @@redis.hgetall(redis_key).symbolize_keys!
        base_redis_key = "users:#{@user[:username]}:tasks:#{task[:id]}"

        redis_key = "#{base_redis_key}:revisions"
        last_revision_num = @@redis.llen(redis_key) - 1
        task.merge!({:last_revision_num => last_revision_num})

        redis_key = "#{base_redis_key}:releases"
        last_release_num = @@redis.llen(redis_key) - 1
        task.merge!({:last_release_num => last_release_num})

        redis_key = "#{base_redis_key}:editing"
        is_editing = !!(@@redis.get(redis_key))
        task.merge!({:is_editing => is_editing})

        redis_key = "#{base_redis_key}:frozen"
        is_frozen = !!(@@redis.get(redis_key))
        task.merge!({:is_frozen => is_frozen})
      end
      @tasks.sort! {|a,b| a[:id].to_i <=> b[:id].to_i }

      erb :tasks_index
    end

    # Admin tasks
    # ==========================================================================
    get "/admin/tasks/:username/:task_id/freeze" do |username, task_id|
      permission_required! :admin, :staff
      redis_key = "users:#{username}:tasks:#{task_id}:frozen"
      @@redis.set(redis_key, "yes")

      text = %Q{#{@user[:username]} freezes #{username}'s task #{task_id}}
      send_notification(@user[:username], "admin", text)
      redirect to("/admin/tasks?username=#{username}")
    end

    get "/admin/tasks/:username/:task_id/unfreeze" do |username, task_id|
      permission_required! :admin, :staff
      redis_key = "users:#{username}:tasks:#{task_id}:frozen"
      @@redis.del(redis_key)

      text = %Q{#{@user[:username]} unfreezes #{username}'s task #{task_id}}
      send_notification(@user[:username], "admin", text)
      redirect to("/admin/tasks?username=#{username}")
    end

    get "/admin/tasks" do
      permission_required! :admin, :staff

      redis_keys = @@redis.keys("tasks:*")
      @tasks = redis_keys.map do |redis_key|
        task = @@redis.hgetall(redis_key).symbolize_keys!
      end
      @tasks.sort! {|a,b| a[:id] <=> b[:id] }

      # filter given user
      if params[:username]
        username = params[:username].downcase
        redis_keys = @@redis.keys("users:#{username}").select{|n| n.count(":") == 1 }
      else
        redis_keys = @@redis.keys("users:*").select {|n| n.count(":") == 1 } # filter out users' properties
      end


      @users = redis_keys.map do |redis_key|
        username = redis_key.split(":")[1]
        user = @@redis.hgetall(redis_key).symbolize_keys!
        user.merge!({:username => username})
        user.merge!({:tasks_frozen => {}})
        @tasks.each do |task|
          the_redis_key = "users:#{username}:tasks:#{task[:id]}:frozen"
          is_frozen = !!@@redis.get(the_redis_key)
          user[:tasks_frozen][task[:id]] = is_frozen
        end
        user
      end
      @users.sort! {|a,b| a[:username] <=> b[:username]}

      if params[:by_task].nil?
        erb :admin_tasks_list
      else
        erb :admin_tasks_list2
      end
    end

    # Admin users
    # ==========================================================================
    get "/admin/users" do
      permission_required!
      redis_keys = @@redis.keys("users:*").select {|n| n.count(":") == 1 } # filter out users' properties
      @users = redis_keys.map do |redis_key|
        username = redis_key.split(":")[1]
        user = @@redis.hgetall(redis_key).symbolize_keys!
        user.merge!({:username => username})
      end
      @users.sort! {|a,b| a[:username] <=> b[:username]}
      erb :admin_users_list
    end

    get "/admin/users/:username" do |username|
      permission_required!
      redis_key = "users:#{username}"
      @the_user = @@redis.hgetall(redis_key).symbolize_keys!
      @the_user.merge!({:username => username})
      erb :admin_users_edit
    end

    post "/admin/users" do
      permission_required!
      username = params[:username].downcase
      password = params[:password]
      role = params[:role] || "user"
      lang = params[:lang] # zh-TW
      country = params[:country] # Taiwan
      direction = params[:direction] || "ltr"
      font = params[:font]

      redis_key = "users:#{username}"
      fields = [:password, :role, :lang, :country, :direction, :font, :plaintext_editor]
      fields.each do |field|
        @@redis.hset(redis_key, field, params[field])
      end

      # initialize tasks
      tasks_keys = @@redis.keys("tasks:*").select{|k| k.count(":") == 1}
      tasks_keys.each do |task_key|
        task_id = task_key.split(":")[1]
        task_text = @@redis.hget(task_key, :initial_text)
        redis_key = "users:#{username}:tasks:#{task_id}:revisions"
        @@redis.rpush(redis_key, {
          :text => task_text,
          :created_at => Time.now.strftime("%s.%L"),
          :created_from => "127.0.0.1"
        }.to_json)
      end

      flash[:info] = %Q{User "#{username}" created successfully.}
      redirect to("/admin/users/#{username}")
    end

    put "/admin/users/:username" do |username|
      permission_required!
      redis_key = "users:#{username}"
      fields = [:password, :role, :lang, :country, :direction, :font]
      fields.each do |field|
        @@redis.hset(redis_key, field, params[field])
      end
      flash[:info] = %Q{User "#{username}" updated successfully.}
      redirect to("/admin/users/#{username}")
    end

    delete "/admin/users/:username" do |username|
      permission_required!
      @@redis.del("users:#{username}") # soft deletion
      flash[:info] = %Q{User "#{username}" deleted successfully.}
      redirect to("/admin/users")
    end

    # Admin notifications
    # ==========================================================================
    get "/admin/notifications" do
      permission_required!
      redis_key = "notifications"
      @notifications = @@redis.lrange(redis_key, 0, -1).map do |item|
        JSON.parse(item).symbolize_keys!
      end
      @notifications.sort! {|a,b| b[:created_at] <=> a[:created_at] }
      erb :admin_notifications_list
    end

    get "/admin/notifications/new" do
      permission_required!
      erb :admin_notifications_new
    end

    post "/admin/notifications" do
      permission_required!
      from = params[:from] || @user[:username]
      to = params[:to] # ".*" means all
      text = params[:text]
      send_notification(from, to, text)
      redirect to("/admin/notifications")
    end
  end
end


# notification server
module LinguistNotification
  class App < Sinatra::Base
    redis_connection = Redis.new(:thread_safe => true)
    @@redis = Redis::Namespace.new(:linguist, :redis => redis_connection)

    get "/updates.json" do
      username = params[:username] rescue nil
      last_seen = params[:time].to_f rescue 0
      redis_key = "notifications"

      # fixme: use pub/sub instead of long-polling
      polling_started_at = Time.now.to_i
      while (Time.now.to_i - polling_started_at) < 60
        notifications = @@redis.lrange(redis_key, -100, -1).map do |item|
          JSON.parse(item).symbolize_keys!
        end

        wanted_notifications = notifications
          .select {|n| n[:created_at].to_f >= last_seen }
          .select {|n| username =~ Regexp.new(n[:to]) || username.nil? }

        if not wanted_notifications.empty?
          return wanted_notifications.to_json
        end
        sleep(1) # in second
      end
      return {}.to_json
    end
  end
end
