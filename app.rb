# frozen_string_literal: true
require 'webrick'
require_relative 'lib/portfolio/config'
require_relative 'lib/portfolio/http_app'

module Portfolio
  def self.build_server(config:, repository: nil, logger: nil)
    repository ||= Repository.new(config.storage_dir, max_upload_bytes: config.max_upload_bytes,
      max_storage_bytes: config.max_storage_bytes)
    logger ||= WEBrick::Log.new($stderr, WEBrick::Log::INFO)
    app = HTTPApp.new(config: config, repository: repository, logger: logger)
    server = WEBrick::HTTPServer.new(Port: config.port, BindAddress: config.bind,
      Logger: logger, AccessLog: [], MaxClients: 8, RequestTimeout: 20,
      DoNotReverseLookup: true, ServerSoftware: 'Portfolio')
    server.mount_proc('/') { |request, response| app.call(request, response) }
    server
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Portfolio::Config.load_env(File.join(__dir__, '.env'))
    config = Portfolio::Config.new(root: __dir__)
    abort('공개 배포에는 Puma를 사용하세요: bundle exec puma -C config/puma.rb') if config.production?
    abort('개발 서버는 로컬 주소에만 바인딩할 수 있습니다. 공개 배포에는 Puma를 사용하세요') unless %w[127.0.0.1 localhost ::1].include?(config.bind)
    if Gem::Version.new(WEBrick::VERSION) < Gem::Version.new('1.9.2')
      message = 'WEBrick 1.9.2 이상으로 업데이트해 주세요: gem install webrick -v "~> 1.9"'
      abort(message) if config.production?
      warn(message)
    end
    repository = Portfolio::Repository.new(config.storage_dir,
      max_upload_bytes: config.max_upload_bytes, max_storage_bytes: config.max_storage_bytes)
    abort('먼저 관리자 계정을 만들어 주세요: ruby bin/setup --demo') unless repository.admin
    server = Portfolio.build_server(config: config, repository: repository)
    trap('INT') { server.shutdown }
    trap('TERM') { server.shutdown }
    puts "\nPortfolio: #{config.app_url}\nAdmin:     #{config.app_url}/admin\n종료: Ctrl+C\n\n"
    server.start
  rescue ArgumentError => e
    abort("설정 오류: #{e.message}")
  end
end
