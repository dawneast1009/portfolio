# frozen_string_literal: true
require_relative 'config'
require_relative 'repository'

module Portfolio
  # Render startup only. Local development continues to use bin/setup + app.rb.
  module Deployment
    def self.prepare!(root:, env: ENV)
      # Read once, and never pass the bootstrap password to the Puma process.
      password = env.delete('ADMIN_PASSWORD')
      env['APP_ENV'] = 'production'
      env['BIND'] = '0.0.0.0'
      env['PORT'] = '10000' if env['PORT'].to_s.empty?
      env['APP_URL'] = env['RENDER_EXTERNAL_URL'] if env['APP_URL'].to_s.empty?
      raise ArgumentError, 'APP_URL 또는 RENDER_EXTERNAL_URL에 HTTPS 주소를 설정하세요' if env['APP_URL'].to_s.empty?
      raise ArgumentError, 'STORAGE_DIR에 저장 경로를 명시하세요' if env['STORAGE_DIR'].to_s.empty?

      settings = Config.new(root: root, env: env)
      bootstrap = lambda do |persistence|
        repository = Repository.new(settings.storage_dir,
          max_upload_bytes: settings.max_upload_bytes, max_storage_bytes: settings.max_storage_bytes,
          persistence: persistence)
        unless repository.admin
          if password.to_s.empty?
            raise ArgumentError, '첫 실행에는 Render 환경변수 ADMIN_PASSWORD가 필요합니다 (15자 이상)'
          end
          username = env['ADMIN_USERNAME'].to_s.empty? ? 'admin' : env['ADMIN_USERNAME']
          repository.setup_admin(username, password)
          repository.seed_demo if env['SEED_DEMO'] == 'true'
        end
        repository.seed_hardcoded_content!(pdf_path: File.join(root, 'assets', 'career-worksheet.pdf'))
        repository
      end

      begin
        bootstrap.call(SupabasePersistence.from_env(env))
      rescue PersistenceError => e
        warn "Supabase 저장을 사용할 수 없어 기본 콘텐츠로 실행합니다 (#{e.message})"
        %w[SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY SUPABASE_SECRET_KEY].each { |key| env.delete(key) }
        bootstrap.call(nil)
      end
      settings
    end
  end
end
