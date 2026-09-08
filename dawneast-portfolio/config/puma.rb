# frozen_string_literal: true
require_relative '../lib/portfolio/config'
root = File.expand_path('..', __dir__)
Portfolio::Config.load_env(File.join(root, '.env'))
settings = Portfolio::Config.new(root: root)
directory root
rackup File.join(root, 'config.ru')
environment settings.environment
bind "tcp://#{settings.bind}:#{settings.port}"
# A single process is required for this PStore + in-memory session design.
workers 0
threads 1, 8
persistent_timeout 20
first_data_timeout 20
http_content_length_limit settings.max_upload_bytes + 2 * 1024 * 1024
