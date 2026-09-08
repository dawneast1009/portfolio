# frozen_string_literal: true
require_relative 'lib/portfolio/config'
require_relative 'lib/portfolio/rack_app'
Portfolio::Config.load_env(File.join(__dir__, '.env'))
config = Portfolio::Config.new(root: __dir__)
repository = Portfolio::Repository.new(config.storage_dir, max_upload_bytes: config.max_upload_bytes,
  max_storage_bytes: config.max_storage_bytes)
abort('먼저 관리자 계정을 만들어 주세요: ruby bin/setup --demo') unless repository.admin
run Portfolio::RackApp.new(config: config, repository: repository)
