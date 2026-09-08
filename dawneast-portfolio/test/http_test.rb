# frozen_string_literal: true
require 'minitest/autorun'
require 'net/http'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require_relative '../app'

class HttpTest < Minitest::Test
  PASSWORD = 'a-long-local-test-password!'

  def setup
    @directory = Dir.mktmpdir('portfolio-http-')
    @config = Portfolio::Config.new(root: File.expand_path('..', __dir__), env: {
      'PORT' => '0', 'STORAGE_DIR' => @directory, 'BIND' => '127.0.0.1',
      'APP_URL' => 'http://127.0.0.1', 'APP_ENV' => 'test'
    })
    @repo = Portfolio::Repository.new(@directory)
    @repo.setup_admin('admin', PASSWORD)
    @server = Portfolio.build_server(config: @config, repository: @repo,
      logger: WEBrick::Log.new(ENV['TEST_DEBUG'] ? $stderr : File::NULL, WEBrick::Log::ERROR))
    @thread = Thread.new { @server.start }
    100.times do
      break if @server.status == :Running
      sleep 0.01
    end
    @port = @server.config[:Port]
    @cookie = nil
  end

  def teardown
    @server&.shutdown
    @thread&.join
    FileUtils.remove_entry(@directory)
  end

  def request(method, path, form: nil, headers: {}, body: nil, cookie: true)
    uri = URI("http://127.0.0.1:#{@port}#{path}")
    klass = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'HEAD' => Net::HTTP::Head }.fetch(method)
    req = klass.new(uri)
    req['Cookie'] = @cookie if @cookie && cookie
    headers.each { |k, v| req[k] = v }
    req.set_form_data(form) if form
    req.body = body if body
    response = Net::HTTP.start(uri.host, uri.port, nil, nil, nil, nil) { |http| http.request(req) }
    set_cookie = response.get_fields('set-cookie')&.find { |line| line.start_with?('portfolio_session=') }
    @cookie = set_cookie.split(';').first if set_cookie && cookie
    response
  end

  def csrf(response)
    response.body[/name="_csrf" value="([0-9a-f]+)"/, 1] || raise('CSRF field is missing')
  end

  def login
    page = request('GET', '/admin/login')
    result = request('POST', '/admin/login', form: { '_csrf' => csrf(page), 'username' => 'admin', 'password' => PASSWORD })
    assert_equal '303', result.code
    csrf(request('GET', '/admin'))
  end

  def make_project(status = 'published')
    @repo.save_project({ 'title' => 'HTTP Project', 'summary' => 'This is a web test', 'body' => '<script>alert(1)</script>',
      'category' => 'development', 'tags' => 'Ruby', 'status' => status })
  end

  def test_home_and_static_assets_load_without_authentication
    assert_equal '200', request('GET', '/').code
    assert_equal '200', request('GET', '/assets/site.css').code
    assert_equal '200', request('GET', '/assets/app.js').code
    assert_equal '404', request('GET', '/storage/portfolio.pstore').code
    assert_equal '404', request('GET', '/assets/../app.rb').code
  end

  def test_private_admin_redirects_to_login
    response = request('GET', '/admin/files')
    assert_equal '303', response.code
    assert response['location'].end_with?('/admin/login')
  end

  def test_csrf_is_required_for_login
    request('GET', '/admin/login')
    response = request('POST', '/admin/login', form: { 'username' => 'admin', 'password' => PASSWORD })
    assert_equal '403', response.code
    assert_equal '303', request('GET', '/admin').code
  end

  def test_login_rotates_and_logout_revokes_session
    page = request('GET', '/admin/login')
    old_cookie = @cookie
    response = request('POST', '/admin/login', form: { '_csrf' => csrf(page), 'username' => 'admin', 'password' => PASSWORD })
    assert_equal '303', response.code
    refute_equal old_cookie, @cookie
    authenticated_cookie = @cookie
    page = request('GET', '/admin')
    assert_equal '200', page.code
    assert_equal '303', request('POST', '/admin/logout', form: { '_csrf' => csrf(page) }).code
    @cookie = authenticated_cookie
    assert_equal '303', request('GET', '/admin').code
  end

  def test_cross_origin_mutation_is_rejected
    token = login
    response = request('POST', '/admin/projects', form: { '_csrf' => token }, headers: { 'Origin' => 'https://untrusted.example' })
    assert_equal '403', response.code
    assert_empty @repo.projects
  end

  def test_draft_and_its_files_are_not_public
    p = make_project('draft')
    f = @repo.add_file(filename: 'notes.txt', bytes: 'private notes', project_id: p['id'], public: true)
    assert_equal '404', request('GET', "/projects/#{p['id']}").code
    assert_equal '404', request('GET', "/files/#{f['id']}/download").code
    refute_includes request('GET', '/files').body, 'notes.txt'
    login
    assert_equal '200', request('GET', "/projects/#{p['id']}").code
    assert_equal 'private notes', request('GET', "/files/#{f['id']}/download").body
  end

  def test_project_body_is_html_escaped
    p = make_project
    response = request('GET', "/projects/#{p['id']}")
    assert_equal '200', response.code
    assert_includes response.body, '&lt;script&gt;'
    refute_includes response.body, '<script>alert(1)</script>'
  end

  def test_real_multipart_upload_and_download
    token = login
    boundary = 'PortfolioTestBoundary1234'
    body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\n#{token}\r\n"
    body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"public\"\r\n\r\n1\r\n"
    body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"label\"\r\n\r\nTest attachment\r\n"
    body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"hello.txt\"\r\nContent-Type: text/plain\r\n\r\nhello from Ruby\r\n--#{boundary}--\r\n"
    response = request('POST', '/admin/files', body: body, headers: { 'Content-Type' => "multipart/form-data; boundary=#{boundary}" })
    assert_equal '303', response.code
    f = @repo.files.first
    refute_nil f
    downloaded = request('GET', "/files/#{f['id']}/download", cookie: false)
    assert_equal 'hello from Ruby', downloaded.body
    assert downloaded['content-disposition'].start_with?('attachment;')
    assert_equal 'nosniff', downloaded['x-content-type-options']
    assert_equal '404', request('GET', "/files/#{f['id']}/preview").code
  end

  def test_contact_is_saved_not_emailed_and_honeypot_is_ignored
    page = request('GET', '/contact')
    fields = { '_csrf' => csrf(page), 'name' => 'Visitor', 'email' => 'visitor@example.com', 'message' => 'A local message', 'consent' => '1' }
    assert_equal '303', request('POST', '/contact', form: fields).code
    assert_equal 1, @repo.messages.size
    assert_equal '303', request('POST', '/contact', form: fields.merge('website' => 'spam')).code
    assert_equal 1, @repo.messages.size
  end

  def test_password_change_invalidates_other_authenticated_session
    login
    first_cookie = @cookie
    @cookie = nil
    token = login
    response = request('POST', '/admin/password', form: { '_csrf' => token, 'current_password' => PASSWORD,
      'new_password' => 'a-brand-new-local-password!', 'confirm_password' => 'a-brand-new-local-password!' })
    assert_equal '303', response.code
    @cookie = first_cookie
    assert_equal '303', request('GET', '/admin').code
  end

  def test_request_body_is_limited_and_host_is_checked
    response = request('POST', '/contact', body: 'a' * (300 * 1024), headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
    assert_equal '413', response.code
    assert_equal '403', request('GET', '/', headers: { 'Host' => 'untrusted.example' }).code
  end

  def test_security_headers_and_cookie_flags
    response = request('GET', '/admin/login')
    assert_includes response['content-security-policy'], "frame-ancestors 'none'"
    assert_equal 'no-store', response['cache-control']
    cookie = response['set-cookie']
    assert_includes cookie, 'HttpOnly'
    assert_includes cookie, 'SameSite=Lax'
  end
  def test_all_admin_screens_render
    login
    %w[/admin/projects /admin/projects/new /admin/files /admin/profile /admin/inbox /admin/security].each do |path|
      response = request('GET', path)
      assert_equal '200', response.code, "#{path}: #{response.body[0, 200]}"
    end
  end

  def test_file_page_preselects_the_linked_project
    p = make_project
    login
    response = request('GET', "/admin/files?project_id=#{p['id']}")
    assert_match(/value="#{p['id']}" selected/, response.body)
  end

  def test_contact_requires_explicit_consent
    page = request('GET', '/contact')
    response = request('POST', '/contact', form: { '_csrf' => csrf(page), 'name' => 'Visitor',
      'email' => 'visitor@example.com', 'message' => 'A test message' })
    assert_equal '422', response.code
    assert_empty @repo.messages
  end

  def test_project_create_update_delete_through_http
    token = login
    fields = { '_csrf' => token, 'title' => 'New project', 'summary' => 'Created through HTTP',
      'body' => 'A real form post', 'category' => 'development', 'tags' => 'Ruby', 'status' => 'draft' }
    response = request('POST', '/admin/projects', form: fields)
    assert_equal '303', response.code
    id = @repo.projects.first['id']
    assert_equal 'draft', @repo.project(id)['status']
    assert_equal '200', request('GET', "/admin/projects/#{id}/edit").code
    assert_equal '303', request('POST', "/admin/projects/#{id}", form: fields.merge('status' => 'published')).code
    assert_equal '200', request('GET', "/projects/#{id}", cookie: false).code
    assert_equal '303', request('POST', "/admin/projects/#{id}/delete", form: { '_csrf' => token }).code
    assert_nil @repo.project(id)
  end

  def test_unicode_filename_upload_and_invalid_file_rejection
    token = login
    boundary = 'PortfolioUnicode123'
    [['자료.txt', '안녕하세요', '303'], ['invalid.pdf', 'not a pdf', '422']].each do |filename, bytes, expected|
      body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\n#{token}\r\n"
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\nContent-Type: application/octet-stream\r\n\r\n#{bytes}\r\n--#{boundary}--\r\n"
      response = request('POST', '/admin/files', body: body, headers: { 'Content-Type' => "multipart/form-data; boundary=#{boundary}" })
      assert_equal expected, response.code
    end
    assert_equal ['자료.txt'], @repo.files.map { |f| f['filename'] }
    f = @repo.files.first
    response = request('GET', "/files/#{f['id']}/download")
    assert_equal '안녕하세요', response.body.force_encoding('UTF-8')
    assert_includes response['content-disposition'], "filename*=UTF-8''%EC%9E%90%EB%A3%8C.txt"
  end

  def test_duplicate_multipart_fields_are_rejected
    token = login
    boundary = 'PortfolioDuplicate123'
    body = [token, token].map { |v| "--#{boundary}\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\n#{v}\r\n" }.join
    body << "--#{boundary}--\r\n"
    response = request('POST', '/admin/files', body: body, headers: { 'Content-Type' => "multipart/form-data; boundary=#{boundary}" })
    assert_equal '400', response.code
    assert_empty @repo.files
  end

  def test_image_cover_visibility_and_file_deletion_through_http
    p = make_project
    png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aU9sAAAAASUVORK5CYII='.unpack1('m0')
    f = @repo.add_file(filename: 'cover.png', bytes: png, project_id: p['id'], public: true)
    token = login
    assert_equal '303', request('POST', "/admin/files/#{f['id']}/cover", form: { '_csrf' => token }).code
    assert_equal f['id'], @repo.project(p['id'])['cover_id']
    page = request('GET', "/projects/#{p['id']}", cookie: false)
    assert_includes page.body, "/files/#{f['id']}/preview"
    assert_equal png, request('GET', "/files/#{f['id']}/preview", cookie: false).body
    assert_equal '303', request('POST', "/admin/files/#{f['id']}/visibility", form: { '_csrf' => token }).code
    assert_equal '404', request('GET', "/files/#{f['id']}/preview", cookie: false).code
    refute_includes request('GET', "/projects/#{p['id']}", cookie: false).body, "/files/#{f['id']}/preview"
    assert_equal '303', request('POST', "/admin/files/#{f['id']}/delete", form: { '_csrf' => token }).code
    refute File.exist?(@repo.file_path(f))
  end

  def test_profile_update_and_resume_link
    f = @repo.add_file(filename: 'resume.pdf', bytes: "%PDF-1.7\n%%EOF", public: true)
    token = login
    fields = { '_csrf' => token, 'display_name' => 'Portfolio Owner', 'headline' => 'New headline', 'resume_id' => f['id'] }
    assert_equal '303', request('POST', '/admin/profile', form: fields).code
    assert_includes request('GET', '/', cookie: false).body, 'New headline'
    assert_includes request('GET', '/about', cookie: false).body, "/files/#{f['id']}/download"
    request('POST', "/admin/files/#{f['id']}/visibility", form: { '_csrf' => token })
    refute_includes request('GET', '/about', cookie: false).body, "/files/#{f['id']}/download"
  end

  def test_inbox_read_delete_and_escaped_message
    message = @repo.add_message('name' => 'Reader', 'email' => 'reader@example.com', 'message' => '<script>hello</script>')
    token = login
    page = request('GET', '/admin/inbox')
    assert_equal '200', page.code
    assert_includes page.body, '&lt;script&gt;hello&lt;/script&gt;'
    assert_equal '303', request('POST', "/admin/inbox/#{message['id']}/read", form: { '_csrf' => token }).code
    assert @repo.messages.first['read']
    assert_equal '303', request('POST', "/admin/inbox/#{message['id']}/delete", form: { '_csrf' => token }).code
    assert_empty @repo.messages
  end

  def test_demo_removal_and_public_search
    @repo.seed_demo
    assert_includes request('GET', '/projects?q=Fuzzing').body, 'Fuzzing Notes'
    refute_includes request('GET', '/projects?q=Fuzzing').body, 'CTF-DAWN'
    token = login
    assert_equal '303', request('POST', '/admin/demo/clear', form: { '_csrf' => token }).code
    assert_empty @repo.projects
    assert_empty @repo.files
    assert_empty Dir.glob(File.join(@directory, 'uploads', '*'))
  end

end
