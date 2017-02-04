# config valid only for current version of Capistrano
lock "3.7.1"

set :application, "ssc"
set :scm, :copy

set :include_dir, ['bin', 'config', 'public']
# set :exclude_dir, ['*']

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, "/opt/ssc"

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
set :format_options, log_file: "logs/capistrano.log"

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
append :linked_files, 'config/secrets.json', 'config/keys.json', 'config/servers.json'

# Default value for linked_dirs is []
append :linked_dirs, 'logs'

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
set :keep_releases, 5

# Use copy deployment
require 'capistrano/copy'

namespace :deploy do
  desc 'Build using dub'
  task :build do
    run_locally do
      execute 'mkdir -p bin'
      # Build using production env
      execute 'dub build -c production'
    end
  end
  after :check, :build

  # desc 'Copy to server'
  # task :copy do
  #   run_locally
  # end
end
