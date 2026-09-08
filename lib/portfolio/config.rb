# frozen_string_literal: true
require 'uri'

module Portfolio
  class Config
    attr_reader :root, :port, :bind, :storage_dir, :app_url, :environment, :max_upload_bytes, :max_storage_bytes

    def self.load_env(path)
      return unless File.file?(path)
      File.foreach(path, encoding: 'UTF-8') do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        match = line.match(/\A([A-Z][A-Z0-9_]*)=(.*)\z/)
        raise ArgumentError, 'Invalid .env line; expected KEY=value' unless match
        value = match[2].strip
        value = value[1...-1] if value.length >= 2 && ((value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'")))
        ENV[match[1]] ||= value
      end
    end

    def initialize(root:, env: ENV)
      @root = File.expand_path(root)
      @environment = env.fetch('APP_ENV', 'development')
      @port = Integer(env.fetch('PORT', '4567'))
      raise ArgumentError, 'PORT must be between 0 and 65535' unless (0..65_535).cover?(@port)
      @bind = env.fetch('BIND', '127.0.0.1')
      @storage_dir = File.expand_path(env.fetch('STORAGE_DIR', 'storage'), @root)
      public_dir = File.join(@root, 'public')
      if @storage_dir == public_dir || @storage_dir.start_with?(public_dir + File::SEPARATOR)
        raise ArgumentError, 'STORAGE_DIR must be outside public/'
      end
      @app_url = env.fetch('APP_URL', "http://localhost:#{@port}").delete_suffix('/')
      uri = URI.parse(@app_url)
      unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && ['', '/'].include?(uri.path.to_s) && !uri.query && !uri.fragment
        raise ArgumentError, 'APP_URL must be an HTTP(S) origin, without a path'
      end
      raise ArgumentError, 'Production APP_URL must use HTTPS' if production? && uri.scheme != 'https'
      @max_upload_bytes = integer_mb(env.fetch('MAX_UPLOAD_MB', '10'), 1..100)
      @max_storage_bytes = integer_mb(env.fetch('MAX_STORAGE_MB', '500'), 1..100_000)
    end

    def production? = @environment == 'production'

    def allowed_hosts
      list = [URI.parse(@app_url).host]
      list.concat(%w[localhost 127.0.0.1 ::1]) unless production?
      list.uniq
    end

    def allowed_origins
      list = [@app_url]
      list.concat(["http://localhost:#{@port}", "http://127.0.0.1:#{@port}"]) unless production?
      list.uniq
    end

    private

    def integer_mb(value, range)
      number = Integer(value)
      raise ArgumentError, 'Invalid storage/upload size configuration' unless range.cover?(number)
      number * 1024 * 1024
    end
  end
end
