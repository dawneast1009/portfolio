# frozen_string_literal: true
require_relative 'http_app'

module Portfolio
  # Production entry point: Puma handles the HTTP wire protocol. The same
  # request handlers/domain code are used by both servers. No WEBrick server
  # is started here; its bounded multipart/cookie utility functions are reused.
  class RackApp
    def initialize(config:, repository: nil, logger: nil)
      repository ||= Repository.new(config.storage_dir, max_upload_bytes: config.max_upload_bytes,
        max_storage_bytes: config.max_storage_bytes)
      logger ||= WEBrick::Log.new($stderr, WEBrick::Log::INFO)
      @app = HTTPApp.new(config: config, repository: repository, logger: logger)
    end

    def call(env)
      request = RackRequest.new(env)
      response = RackResponse.new
      @app.call(request, response)
      body = response.body
      if body.is_a?(String)
        response['content-length'] ||= body.bytesize.to_s
        body = [body]
      elsif body.respond_to?(:read)
        body = FileBody.new(body)
      else
        body = []
      end
      if request.request_method == 'HEAD'
        body.close if body.respond_to?(:close)
        body = []
      end
      [response.status, response.headers, body]
    end
  end

  class RackRequest
    def initialize(env) = @env = env
    def path = @env.fetch('PATH_INFO', '/')
    def request_method = @env.fetch('REQUEST_METHOD', 'GET')
    def query_string = @env.fetch('QUERY_STRING', '')
    def content_length = @env['CONTENT_LENGTH'].to_i
    def peeraddr = [nil, nil, nil, @env.fetch('REMOTE_ADDR', 'unknown')]

    def host
      authority = @env.fetch('HTTP_HOST', @env.fetch('SERVER_NAME', ''))
      match = authority.match(/\A([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(?::\d{1,5})?\z/)
      match ? match[1].delete_prefix('[').delete_suffix(']').downcase : ''
    end

    def [](name)
      key = name.upcase.tr('-', '_')
      key = 'HTTP_' + key unless %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
      @env[key]
    end

    def cookies = WEBrick::Cookie.parse(@env.fetch('HTTP_COOKIE', ''))

    def body
      input = @env['rack.input']
      return unless input
      while (chunk = input.read(64 * 1024)) && !chunk.empty?
        yield chunk
      end
    end
  end

  class RackResponse
    attr_accessor :status, :body, :keep_alive
    attr_reader :headers
    def initialize
      @status, @body, @headers = 200, '', {}
    end
    def [](name) = @headers[name.downcase]
    def []=(name, value)
      @headers[name.downcase] = value
    end
  end

  class FileBody
    def initialize(io) = @io = io
    def each
      while (chunk = @io.read(64 * 1024))
        yield chunk
      end
    end
    def close
      @io.close unless @io.closed?
    end
  end
end
