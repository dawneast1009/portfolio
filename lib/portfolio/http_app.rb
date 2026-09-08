# frozen_string_literal: true
require 'webrick'
require 'stringio'
require 'uri'
require_relative 'config'
require_relative 'repository'
require_relative 'view'

module Portfolio
  class HTTPError < StandardError
    attr_reader :status
    def initialize(status, message)
      @status = status
      super(message)
    end
  end

  UploadPart = Struct.new(:filename, :bytes, keyword_init: true)

  class HTTPApp
    def initialize(config:, repository:, logger:)
      @config, @repository, @logger = config, repository, logger
      @sessions, @limiter = Sessions.new, RateLimiter.new
    end

    def call(request, response)
      RequestContext.new(@config, @repository, @sessions, @limiter, @logger, request, response).call
    end
  end

  class RequestContext
    ASSETS = { '/assets/site.css' => ['site.css', 'text/css; charset=utf-8'],
      '/assets/app.js' => ['app.js', 'application/javascript; charset=utf-8'],
      '/assets/favicon.svg' => ['favicon.svg', 'image/svg+xml'] }.freeze
    ID = '[0-9a-f]{24}'

    def initialize(config, repo, sessions, limiter, logger, request, response)
      @config, @repo, @sessions, @limiter, @logger = config, repo, sessions, limiter, logger
      @req, @res = request, response
      @path = request.path
      @authenticated = false
      @params = {}
      @query = {}
    end

    def call
      set_headers
      raise HTTPError.new(403, '허용되지 않은 호스트입니다. APP_URL 설정을 확인해 주세요') unless @config.allowed_hosts.include?(@req.host.to_s.downcase)
      method = @req.request_method
      raise HTTPError.new(405, '허용되지 않은 요청 방식입니다') unless %w[GET HEAD POST].include?(method)
      if ASSETS.key?(@path) && %w[GET HEAD].include?(method)
        return serve_asset
      end
      load_session
      @query = parse_pairs(@req.query_string.to_s, max_bytes: 8192)
      if @path.start_with?('/admin') && @path != '/admin/login' && !@authenticated
        @res.keep_alive = false if method == 'POST'
        return redirect('/admin/login')
      end
      if method == 'POST'
        @params = parse_body
        verify_csrf!
        dispatch_post
      else
        dispatch_get
      end
    rescue HTTPError => e
      @res.keep_alive = false if [400, 413].include?(e.status)
      render_error(e.status, e.message)
    rescue ValidationError => e
      render_error(422, e.message)
    rescue NotFound
      render_error(404, '페이지 또는 자료를 찾을 수 없습니다')
    rescue WEBrick::HTTPStatus::Status => e
      @res.keep_alive = false
      render_error(e.code, '요청 형식을 확인하고 다시 시도해 주세요')
    rescue StandardError => e
      @logger.error("request=#{@res['X-Request-ID']} #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      render_error(500, '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요')
    end

    private

    def set_headers
      @res['Content-Type'] = 'text/html; charset=utf-8'
      @res['Cache-Control'] = 'no-store'
      @res['X-Content-Type-Options'] = 'nosniff'
      @res['Referrer-Policy'] = 'strict-origin-when-cross-origin'
      @res['X-Frame-Options'] = 'DENY'
      @res['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=()'
      @res['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
      @res['Strict-Transport-Security'] = 'max-age=31536000' if @config.production?
      @res['X-Request-ID'] = SecureRandom.hex(8)
      @res['Server'] = 'Portfolio'
    end

    def load_session
      @token = @req.cookies.find { |cookie| cookie.name == 'portfolio_session' }&.value
      @session = @sessions.lookup(@token)
      version = @session&.fetch('admin_version', nil)
      account = @repo.admin if version
      @authenticated = !!(version && account && Security.constant_compare(version, account['version']))
    end

    def ensure_session
      return if @session
      @token, @session = @sessions.create
      write_cookie(@token)
    end

    def write_cookie(token, expire: false)
      cookie = "portfolio_session=#{token}; Path=/; HttpOnly; SameSite=Lax"
      cookie += "; Max-Age=#{expire ? 0 : Sessions::ABSOLUTE_TTL}"
      cookie += '; Secure' if @config.production?
      @res['Set-Cookie'] = cookie
    end

    def verify_csrf!
      origin = @req['origin']
      if (origin && !@config.allowed_origins.include?(origin)) || @req['sec-fetch-site'] == 'cross-site'
        raise HTTPError.new(403, '다른 사이트에서 보낸 요청은 허용하지 않습니다')
      end
      unless @session && Security.constant_compare(@params['_csrf'], @session['csrf'])
        raise HTTPError.new(403, '폼이 만료되었거나 유효하지 않습니다. 페이지를 새로 열고 다시 시도해 주세요')
      end
    end

    def parse_pairs(string, max_bytes:)
      raise HTTPError.new(413, '요청이 너무 큽니다') if string.bytesize > max_bytes
      pairs = URI.decode_www_form(string, Encoding::UTF_8)
      raise HTTPError.new(400, '입력 항목이 너무 많습니다') if pairs.size > 40
      pairs.each_with_object({}) do |(key, value), result|
        raise HTTPError.new(400, '중복된 입력 항목이 있습니다') if result.key?(key)
        raise HTTPError.new(400, '잘못된 입력 형식입니다') if key.bytesize > 80 || !value.valid_encoding?
        result[key] = value
      end
    rescue ArgumentError
      raise HTTPError.new(400, '입력 형식을 확인해 주세요')
    end

    def parse_body
      limit = @path == '/admin/files' ? @config.max_upload_bytes + 2 * 1024 * 1024 : 256 * 1024
      raise HTTPError.new(413, '요청 용량 제한을 초과했습니다') if @req.content_length.to_i > limit
      body = +''.b
      @req.body do |chunk|
        raise HTTPError.new(413, '요청 용량 제한을 초과했습니다') if body.bytesize + chunk.bytesize > limit
        body << chunk
      end
      type = @req['content-type'].to_s
      if type.start_with?('application/x-www-form-urlencoded')
        return parse_pairs(body, max_bytes: limit)
      end
      unless @path == '/admin/files' && type.start_with?('multipart/form-data')
        raise HTTPError.new(415, '지원하지 않는 요청 형식입니다')
      end
      match = type.match(/boundary=(?:"([^"]+)"|([^;\s]+))/)
      boundary = match && (match[1] || match[2])
      unless boundary && boundary.bytesize <= 70 && boundary.match?(/\A[0-9A-Za-z'()+_,.\/:=? -]+\z/)
        raise HTTPError.new(400, '업로드 요청 형식이 올바르지 않습니다')
      end
      parsed = WEBrick::HTTPUtils.parse_form_data(StringIO.new(body), boundary)
      raise HTTPError.new(400, '입력 항목이 너무 많습니다') if parsed.size > 40
      parsed.each_with_object({}) do |(name, part), result|
        raise HTTPError.new(400, '중복된 입력 항목이 있습니다') if part.enum_for(:each_data).take(2).length > 1
        raise HTTPError.new(400, '잘못된 입력 이름입니다') if name.to_s.bytesize > 80
        if part.filename
          raise HTTPError.new(400, '파일은 한 번에 하나씩 업로드해 주세요') unless name == 'file'
          result[name] = UploadPart.new(filename: part.filename, bytes: part.to_s.b)
        else
          value = part.to_s.dup.force_encoding(Encoding::UTF_8)
          raise HTTPError.new(400, '잘못된 입력 형식입니다') unless value.valid_encoding? && value.bytesize <= 100_000
          result[name] = value
        end
      end
    end

    def dispatch_get
      case @path
      when '/'
        all = @repo.public_projects
        render('home', title: 'Portfolio', projects: all.sort_by { |p| p['featured'] ? 0 : 1 }.first(3),
          files: @repo.public_files.first(3), project_count: all.size, file_count: @repo.public_files.size)
      when '/projects'
        render('projects', title: '프로젝트', projects: @repo.public_projects(query: @query['q'], tag: @query['tag'], category: @query['category']),
          query: @query, tags: @repo.public_projects.flat_map { |p| p['tags'] }.uniq.sort)
      when %r{\A/projects/(#{ID})\z}
        id = Regexp.last_match(1)
        project = @repo.project(id)
        raise NotFound unless project && (project['status'] == 'published' || @authenticated)
        attached = @repo.files.select { |f| f['project_id'] == id && (@authenticated || @repo.public_file?(f)) }
        render('project', title: project['title'], project: project, files: attached)
      when '/files'
        files = @repo.public_files
        query = @query.fetch('q', '').downcase
        files = files.select { |f| "#{f['label']} #{f['filename']}".downcase.include?(query) } unless query.empty?
        render('files', title: '자료실', files: files, query: @query)
      when %r{\A/files/(#{ID})/(download|preview)\z}
        serve_file(Regexp.last_match(1), preview: Regexp.last_match(2) == 'preview')
      when '/about'
        render('about', title: '소개')
      when '/contact'
        ensure_session
        render('contact', title: '연락하기')
      when '/admin/login'
        return redirect('/admin') if @authenticated
        ensure_session
        render('admin/login', title: '관리자 로그인')
      when '/admin'
        render('admin/dashboard', title: '대시보드', projects: @repo.projects,
          files: @repo.files, messages: @repo.messages)
      when '/admin/projects'
        projects = @repo.projects
        status = @query.fetch('status', '')
        projects = projects.select { |p| p['status'] == status } if %w[draft published].include?(status)
        render('admin/projects', title: '프로젝트 관리', projects: projects, query: @query)
      when '/admin/projects/new'
        render_project_form({ 'status' => 'draft', 'category' => 'development', 'year' => Time.now.year.to_s })
      when %r{\A/admin/projects/(#{ID})/edit\z}
        project = @repo.project(Regexp.last_match(1))
        raise NotFound unless project
        render_project_form(project)
      when '/admin/files'
        render_admin_files(values: { 'project_id' => @query['project_id'].to_s })
      when '/admin/profile'
        render('admin/profile', title: '프로필 설정', values: @repo.profile,
          pdfs: @repo.public_files.select { |f| f['mime'] == 'application/pdf' })
      when '/admin/inbox'
        render('admin/inbox', title: '문의함', messages: @repo.messages)
      when '/admin/security'
        render('admin/security', title: '계정 보안', username: @repo.admin['username'])
      else
        raise NotFound
      end
    end

    def dispatch_post
      case @path
      when '/admin/login' then log_in
      when '/admin/logout'
        @sessions.delete(@token)
        write_cookie('', expire: true)
        redirect('/admin/login')
      when '/admin/projects' then save_project
      when %r{\A/admin/projects/(#{ID})\z} then save_project(Regexp.last_match(1))
      when %r{\A/admin/projects/(#{ID})/delete\z}
        @repo.delete_project(Regexp.last_match(1))
        redirect('/admin/projects', '프로젝트와 연결된 파일을 삭제했습니다')
      when '/admin/files' then upload_file
      when %r{\A/admin/files/(#{ID})/(delete|cover|visibility)\z}
        id, operation = Regexp.last_match(1), Regexp.last_match(2)
        case operation
        when 'delete' then @repo.delete_file(id)
        when 'cover' then @repo.set_cover(id)
        when 'visibility' then @repo.toggle_file_visibility(id)
        end
        redirect('/admin/files', '파일 설정을 반영했습니다')
      when '/admin/profile' then save_profile
      when '/admin/password' then change_password
      when %r{\A/admin/inbox/(#{ID})/(read|delete)\z}
        id, operation = Regexp.last_match(1), Regexp.last_match(2)
        operation == 'read' ? @repo.mark_message_read(id) : @repo.delete_message(id)
        redirect('/admin/inbox', operation == 'read' ? '읽음으로 표시했습니다' : '문의를 삭제했습니다')
      when '/admin/demo/clear'
        @repo.clear_demo
        redirect('/admin', '샘플 프로젝트와 샘플 파일을 삭제했습니다')
      when '/contact' then save_contact
      else
        raise NotFound
      end
    end

    def log_in
      unless @limiter.allow?("login:#{remote_ip}", limit: 5, window: 900)
        @res['Retry-After'] = '900'
        return render('admin/login', status: 429, title: '로그인 시도 제한', error: '로그인 시도가 너무 많습니다. 15분 후 다시 시도해 주세요')
      end
      unless @repo.authenticate(@params['username'], @params['password'])
        return render('admin/login', status: 422, title: '관리자 로그인', error: '아이디 또는 비밀번호가 올바르지 않습니다', values: { 'username' => @params['username'].to_s })
      end
      @token, @session = @sessions.rotate(@token, admin_version: @repo.admin['version'])
      write_cookie(@token)
      redirect('/admin', '로그인했습니다')
    end

    def save_project(id = nil)
      project = @repo.save_project(@params, id: id)
      redirect("/admin/projects/#{project['id']}/edit", '프로젝트를 저장했습니다')
    rescue ValidationError => e
      render_project_form(@params.merge('id' => id), error: e.message, status: 422)
    end

    def render_project_form(values, error: nil, status: 200)
      files = @repo.files.select { |f| f['project_id'] == values['id'] && Uploads::IMAGE_MIMES.include?(f['mime']) }
      render('admin/project_form', title: values['id'] ? '프로젝트 수정' : '새 프로젝트',
        values: values, images: files, error: error, status: status)
    end

    def render_admin_files(error: nil, status: 200, values: {})
      render('admin/files', title: '파일 관리', files: @repo.files, projects: @repo.projects,
        values: values, error: error, status: status)
    end

    def upload_file
      file = @params['file']
      raise ValidationError, '업로드할 파일을 선택해 주세요' unless file.is_a?(UploadPart) && !file.filename.to_s.empty?
      @repo.add_file(filename: file.filename, bytes: file.bytes, project_id: @params['project_id'],
        label: @params.fetch('label', ''), public: @params['public'] == '1')
      redirect('/admin/files', '파일을 업로드했습니다')
    rescue ValidationError => e
      render_admin_files(error: e.message, status: 422, values: @params.reject { |key, _v| key == 'file' })
    end

    def save_profile
      @repo.update_profile(@params)
      redirect('/admin/profile', '프로필을 저장했습니다')
    rescue ValidationError => e
      render('admin/profile', title: '프로필 설정', values: @repo.profile.merge(@params), error: e.message, status: 422,
        pdfs: @repo.public_files.select { |f| f['mime'] == 'application/pdf' })
    end

    def change_password
      unless @params['new_password'] == @params['confirm_password']
        raise ValidationError, '새 비밀번호와 확인 값이 일치하지 않습니다'
      end
      @repo.change_password(@params['current_password'], @params['new_password'])
      @token, @session = @sessions.rotate(@token, admin_version: @repo.admin['version'])
      write_cookie(@token)
      redirect('/admin/security', '비밀번호를 변경했습니다. 다른 기기의 로그인은 해제됩니다')
    rescue ValidationError => e
      render('admin/security', title: '계정 보안', username: @repo.admin['username'], error: e.message, status: 422)
    end

    def save_contact
      unless @params.fetch('website', '').to_s.empty?
        return redirect('/contact', '메시지가 전달되었습니다')
      end
      unless @limiter.allow?("contact:#{remote_ip}", limit: 3, window: 600)
        @res['Retry-After'] = '600'
        return render('contact', title: '연락하기', values: @params, error: '메시지가 너무 자주 전송되었습니다. 10분 후 다시 시도해 주세요', status: 429)
      end
      raise ValidationError, '문의 처리를 위한 개인정보 수집에 동의해 주세요' unless @params['consent'] == '1'
      @repo.add_message(@params)
      redirect('/contact', '메시지가 전달되었습니다. 남겨주신 이메일로 답변드릴게요')
    rescue ValidationError => e
      render('contact', title: '연락하기', values: @params, error: e.message, status: 422)
    end

    def serve_asset
      name, content_type = ASSETS.fetch(@path)
      @res['Content-Type'] = content_type
      @res['Cache-Control'] = 'public, max-age=3600'
      @res.body = File.binread(File.join(@config.root, 'public', 'assets', name))
    end

    def serve_file(id, preview:)
      file = @repo.file(id)
      raise NotFound unless file && (@authenticated || @repo.public_file?(file))
      raise NotFound if preview && !Uploads::IMAGE_MIMES.include?(file['mime'])
      path = @repo.file_path(file)
      raise NotFound unless File.file?(path)
      @res['Content-Type'] = file['mime'] + (file['mime'] == 'text/plain' ? '; charset=utf-8' : '')
      fallback = file['filename'].gsub(/[^A-Za-z0-9._-]/, '_')[0, 100]
      encoded = URI.encode_www_form_component(file['filename']).gsub('+', '%20')
      disposition = preview ? 'inline' : 'attachment'
      @res['Content-Disposition'] = "#{disposition}; filename=\"#{fallback}\"; filename*=UTF-8''#{encoded}"
      @res['Content-Security-Policy'] = "default-src 'none'; sandbox"
      @res['Content-Length'] = File.size(path).to_s
      @res.body = File.open(path, 'rb')
    end

    def render(template, title:, status: 200, **data)
      @res.status = status
      @res.body = View.new(config: @config, repository: @repo, path: @path,
        authenticated: @authenticated, csrf: @session&.fetch('csrf', nil),
        flash: @sessions.take_flash(@token), title: title, data: data).render(template)
    end

    def render_error(status, message)
      render('error', title: "#{status} · 요청 안내", status: status, error_code: status, error_message: message)
    rescue StandardError
      @res.status = status
      @res['Content-Type'] = 'text/plain; charset=utf-8'
      @res.body = "#{status} - #{message}"
    end

    def redirect(path, message = nil)
      @sessions.set_flash(@token, message) if message && @token
      @res.status = 303
      @res['Location'] = path
      @res.body = ''
    end

    def remote_ip = @req.peeraddr[3]
  end
end
