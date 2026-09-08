# frozen_string_literal: true
require_relative 'http_test'
require_relative '../lib/portfolio/rack_app' if File.exist?(File.expand_path('../lib/portfolio/rack_app.rb', __dir__))

# Run the identical behavioral suite through Rack's env/response interface.
# This does not claim that a Puma process was started.
class RackTest < HttpTest
  Response = Struct.new(:code, :body, :headers) do
    def [](name) = headers[name.downcase]
    def get_fields(name) = headers.key?(name.downcase) ? Array(headers[name.downcase]) : nil
  end

  def setup
    assert defined?(Portfolio::RackApp), 'The Rack adapter is not implemented yet'
    @directory = Dir.mktmpdir('portfolio-rack-')
    @config = Portfolio::Config.new(root: File.expand_path('..', __dir__), env: {
      'PORT' => '4567', 'STORAGE_DIR' => @directory, 'APP_URL' => 'http://127.0.0.1:4567', 'APP_ENV' => 'test'
    })
    @repo = Portfolio::Repository.new(@directory)
    @repo.setup_admin('admin', PASSWORD)
    @rack = Portfolio::RackApp.new(config: @config, repository: @repo,
      logger: WEBrick::Log.new(ENV['TEST_DEBUG'] ? $stderr : File::NULL, WEBrick::Log::ERROR))
    @cookie = nil
  end

  def teardown
    FileUtils.remove_entry(@directory) if @directory
  end

  def request(method, path, form: nil, headers: {}, body: nil, cookie: true)
    path, query = path.split('?', 2)
    if form
      body = URI.encode_www_form(form)
      headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }.merge(headers)
    end
    env = { 'REQUEST_METHOD' => method, 'PATH_INFO' => path, 'QUERY_STRING' => query.to_s,
      'HTTP_HOST' => '127.0.0.1:4567', 'SERVER_NAME' => '127.0.0.1', 'SERVER_PORT' => '4567',
      'REMOTE_ADDR' => '127.0.0.1', 'rack.url_scheme' => 'http',
      'rack.input' => StringIO.new(body.to_s.b), 'CONTENT_LENGTH' => body.to_s.bytesize.to_s }
    env['HTTP_COOKIE'] = @cookie if cookie && @cookie
    headers.each do |key, value|
      key = key.upcase.tr('-', '_')
      key = 'HTTP_' + key unless %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
      env[key] = value
    end
    status, result_headers, response_body = @rack.call(env)
    assert result_headers.keys.all? { |k| k == k.downcase }, 'Rack 3 headers must be lowercase'
    response = +''.b
    begin
      response_body.each { |chunk| response << chunk }
    ensure
      response_body.close if response_body.respond_to?(:close)
    end
    new_cookie = Array(result_headers['set-cookie']).find { |line| line.start_with?('portfolio_session=') }
    @cookie = new_cookie.split(';').first if new_cookie && cookie
    Response.new(status.to_s, response, result_headers)
  end

  def test_head_response_has_no_body
    response = request('HEAD', '/')
    assert_equal '200', response.code
    assert_empty response.body
    file = @repo.add_file(filename: 'head.txt', bytes: 'head body', public: true)
    response = request('HEAD', "/files/#{file['id']}/download")
    assert_equal '200', response.code
    assert_empty response.body
    assert_equal '9', response['content-length']
  end

  def test_production_sets_secure_cookie_and_hsts
    production = Portfolio::Config.new(root: @config.root, env: {
      'APP_ENV' => 'production', 'APP_URL' => 'https://portfolio.example', 'STORAGE_DIR' => @directory })
    @rack = Portfolio::RackApp.new(config: production, repository: @repo)
    response = request('GET', '/admin/login', headers: { 'Host' => 'portfolio.example' })
    assert_equal '200', response.code
    assert_includes response['set-cookie'], '; Secure'
    assert_equal 'max-age=31536000', response['strict-transport-security']
  end
end
