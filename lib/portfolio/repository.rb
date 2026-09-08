# frozen_string_literal: true
require 'uri'
require 'time'
require 'digest'
require_relative 'security'
require_relative 'store'
require_relative 'uploads'

module Portfolio
  class Repository
    CATEGORIES = { 'development' => '개발', 'security' => '보안', 'research' => '기록', 'design' => '디자인', 'other' => '기타' }.freeze
    attr_reader :max_upload_bytes, :max_storage_bytes

    def initialize(directory, max_upload_bytes: 10 * 1024 * 1024, max_storage_bytes: 500 * 1024 * 1024)
      @directory = File.expand_path(directory)
      @uploads = File.join(@directory, 'uploads')
      FileUtils.mkdir_p(@uploads, mode: 0o700)
      @store = Store.new(@directory)
      @max_upload_bytes, @max_storage_bytes = max_upload_bytes, max_storage_bytes
    end

    def profile = @store.read['profile']
    def admin = @store.read['admin']
    def projects = @store.read['projects'].values.sort_by { |p| p['updated_at'] }.reverse
    def project(id) = @store.read['projects'][id.to_s]
    def files = @store.read['files'].values.sort_by { |f| f['created_at'] }.reverse
    def file(id) = @store.read['files'][id.to_s]
    def messages = @store.read['messages'].values.sort_by { |m| m['created_at'] }.reverse

    def public_projects(query: '', tag: '', category: '')
      projects.select do |p|
        haystack = [p['title'], p['summary'], *p['tags']].join(' ').downcase
        p['status'] == 'published' && (query.to_s.empty? || haystack.include?(query.to_s.downcase)) &&
          (tag.to_s.empty? || p['tags'].any? { |t| t.downcase == tag.to_s.downcase }) &&
          (category.to_s.empty? || p['category'] == category)
      end
    end

    def public_files
      state = @store.read
      state['files'].values.select { |f| public_in_state?(f, state) }.sort_by { |f| f['created_at'] }.reverse
    end

    def public_file?(record)
      return false unless record
      state = @store.read
      # Re-read the canonical record rather than trusting a caller's visibility flag.
      public_in_state?(state['files'][record['id']], state)
    end

    def setup_admin(username, password, reset: false)
      unless username.to_s.match?(/\A[a-zA-Z0-9_.-]{3,40}\z/)
        raise ValidationError, '관리자 아이디는 영문, 숫자, 밑줄, 점, 하이픈으로 3~40자입니다'
      end
      password_record = Security.hash_password(password)
      @store.update do |state|
        raise ValidationError, '관리자가 이미 있습니다. 비밀번호 재설정은 --reset-password를 사용해 주세요' if state['admin'] && !reset
        state['admin'] = { 'username' => username, 'password' => password_record, 'version' => SecureRandom.hex(16) }
      end
    end

    def authenticate(username, password)
      account = admin
      return false unless account
      password_ok = Security.verify_password(password, account['password'])
      Security.constant_compare(username.to_s, account['username']) && password_ok
    end

    def change_password(current_password, new_password)
      account = admin
      raise ValidationError, '현재 비밀번호가 올바르지 않습니다' unless account && Security.verify_password(current_password, account['password'])
      replacement = Security.hash_password(new_password)
      @store.update do |state|
        # Prevent concurrent password-change requests from using a stale credential.
        raise ValidationError, '비밀번호가 변경되었습니다. 다시 로그인해 주세요' unless state['admin']['version'] == account['version']
        state['admin']['password'] = replacement
        state['admin']['version'] = SecureRandom.hex(16)
      end
    end

    def save_project(input, id: nil, demo: false)
      data = {
        'title' => text(input, 'title', max: 100, required: true),
        'summary' => text(input, 'summary', max: 280, required: true),
        'body' => text(input, 'body', max: 30_000),
        'category' => input['category'].to_s,
        'tags' => tag_list(input['tags']),
        'repo_url' => safe_url(input['repo_url']), 'live_url' => safe_url(input['live_url']),
        'status' => input['status'].to_s,
        'featured' => [true, '1', 'on'].include?(input['featured']),
        'year' => text(input, 'year', max: 4),
        'demo' => demo
      }
      data['year'] = Time.now.year.to_s if data['year'].empty?
      raise ValidationError, '연도는 네 자리 숫자로 입력해 주세요' unless data['year'].match?(/\A\d{4}\z/)
      raise ValidationError, '올바른 카테고리를 선택해 주세요' unless CATEGORIES.key?(data['category'])
      raise ValidationError, '공개 또는 비공개 상태를 선택해 주세요' unless %w[published draft].include?(data['status'])
      @store.update do |state|
        old = id ? state['projects'][id] : nil
        raise NotFound, '프로젝트를 찾을 수 없습니다' if id && !old
        project_id = id || SecureRandom.hex(12)
        cover_id = input.key?('cover_id') ? input['cover_id'].to_s : old&.fetch('cover_id', nil)
        unless cover_id.to_s.empty?
          cover = state['files'][cover_id]
          unless cover && cover['project_id'] == project_id && Uploads::IMAGE_MIMES.include?(cover['mime'])
            raise ValidationError, '이 프로젝트에 업로드한 이미지만 대표 이미지로 설정할 수 있습니다'
          end
        end
        data.merge!('id' => project_id, 'cover_id' => cover_id,
          'created_at' => old ? old['created_at'] : timestamp, 'updated_at' => timestamp)
        state['projects'][project_id] = data
        data.dup
      end
    end

    def delete_project(id)
      removed = @store.update do |state|
        raise NotFound, '프로젝트를 찾을 수 없습니다' unless state['projects'].delete(id)
        attached = state['files'].values.select { |f| f['project_id'] == id }
        attached.each { |f| remove_file_record(f['id'], state) }
        attached
      end
      removed.each { |f| unlink_file(f) }
    end

    def add_file(filename:, bytes:, project_id: nil, label: '', public: false, demo: false)
      metadata = Uploads.inspect_file(filename, bytes, max_bytes: @max_upload_bytes)
      name = text({ 'label' => label }, 'label', max: 100)
      metadata.merge!('id' => SecureRandom.hex(12), 'label' => name.empty? ? metadata['filename'] : name,
        'project_id' => project_id.to_s.empty? ? nil : project_id.to_s, 'public' => !!public,
        'created_at' => timestamp, 'sha256' => Digest::SHA256.hexdigest(bytes), 'demo' => demo)
      created = false
      path = file_path(metadata)
      begin
        @store.update do |state|
          if metadata['project_id'] && !state['projects'].key?(metadata['project_id'])
            raise ValidationError, '연결할 프로젝트를 찾을 수 없습니다'
          end
          if state['files'].values.sum { |f| f['size'] } + bytes.bytesize > @max_storage_bytes
            raise ValidationError, '전체 저장 공간이 부족합니다. 사용하지 않는 파일을 삭제해 주세요'
          end
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |handle|
            created = true
            handle.binmode
            handle.write(bytes)
            handle.flush
            handle.fsync
          end
          state['files'][metadata['id']] = metadata
          metadata.dup
        end
      rescue StandardError
        File.unlink(path) if created && File.file?(path)
        raise
      end
    end

    def delete_file(id)
      removed = @store.update do |state|
        record = state['files'][id]
        raise NotFound, '파일을 찾을 수 없습니다' unless record
        remove_file_record(id, state)
        record
      end
      unlink_file(removed)
    end

    def toggle_file_visibility(id)
      @store.update do |state|
        record = state['files'][id]
        raise NotFound, '파일을 찾을 수 없습니다' unless record
        record['public'] = !record['public']
        state['profile']['resume_id'] = '' if !record['public'] && state['profile']['resume_id'] == id
      end
    end

    def set_cover(file_id)
      @store.update do |state|
        record = state['files'][file_id]
        unless record && record['project_id'] && Uploads::IMAGE_MIMES.include?(record['mime'])
          raise ValidationError, '프로젝트에 연결된 이미지 파일을 선택해 주세요'
        end
        project = state['projects'][record['project_id']]
        raise NotFound, '프로젝트를 찾을 수 없습니다' unless project
        project['cover_id'] = file_id
        project['updated_at'] = timestamp
      end
    end

    def file_path(record)
      id = record.fetch('id')
      raise ValidationError, '올바르지 않은 파일 식별자입니다' unless id.match?(/\A[0-9a-f]{24}\z/)
      File.join(@uploads, "#{id}.blob")
    end

    def update_profile(input)
      @store.update do |state|
        current = state['profile']
        merged = current.merge(input.select { |k, _v| Store::DEFAULT_PROFILE.key?(k) })
        data = {}
        { 'display_name' => 40, 'role' => 100, 'headline' => 100, 'intro' => 500,
          'bio' => 6000, 'skills' => 300, 'location' => 80, 'status' => 80 }.each do |key, limit|
          data[key] = text(merged, key, max: limit, required: %w[display_name headline].include?(key))
        end
        %w[github_url blog_url].each { |key| data[key] = safe_url(merged[key]) }
        data['contact_email'] = text(merged, 'contact_email', max: 200)
        validate_email!(data['contact_email']) unless data['contact_email'].empty?
        data['resume_id'] = merged['resume_id'].to_s
        unless data['resume_id'].empty?
          resume = state['files'][data['resume_id']]
          unless public_in_state?(resume, state) && resume['mime'] == 'application/pdf'
            raise ValidationError, '이력서는 공개된 PDF 파일만 선택할 수 있습니다'
          end
        end
        state['profile'] = data
      end
    end

    def add_message(input)
      data = { 'id' => SecureRandom.hex(12), 'name' => text(input, 'name', max: 80, required: true),
        'email' => text(input, 'email', max: 200, required: true),
        'subject' => text(input, 'subject', max: 160),
        'message' => text(input, 'message', max: 5000, required: true),
        'read' => false, 'created_at' => timestamp }
      validate_email!(data['email'])
      @store.update do |state|
        raise ValidationError, '현재 문의함이 가득 찼습니다. 나중에 다시 시도해 주세요' if state['messages'].size >= 2000
        state['messages'][data['id']] = data
        data.dup
      end
    end

    def mark_message_read(id)
      @store.update do |state|
        raise NotFound, '메시지를 찾을 수 없습니다' unless state['messages'][id]
        state['messages'][id]['read'] = true
      end
    end

    def delete_message(id)
      @store.update do |state|
        raise NotFound, '메시지를 찾을 수 없습니다' unless state['messages'].delete(id)
      end
    end

    def seed_demo
      return unless projects.empty?
      samples = [
        ['CTF-DAWN', 'security', 'CTF 플랫폼의 문제와 변경 사항을 모아 보는 도구를 소개하는 샘플 프로젝트입니다.', 'Ruby, API, CTF'],
        ['Fuzzing Notes', 'research', '하네스와 시드부터 실행 결과까지, 실습 과정을 정리하는 샘플 기술 노트입니다.', 'C / C++, Linux, Notes'],
        ['Portfolio Studio', 'development', '프로젝트와 파일을 직접 관리하는 Ruby 기반 포트폴리오의 샘플 소개입니다.', 'Ruby, HTML, CSS']
      ]
      samples.each_with_index do |(title, category, summary, tags), index|
        p = save_project({ 'title' => title, 'category' => category, 'summary' => summary,
          'tags' => tags, 'status' => 'published', 'featured' => index < 2 ? '1' : '',
          'body' => "샘플 프로젝트\n\n화면 구성을 확인하기 위해 넣은 예시입니다. 실제 경력이나 검증된 프로젝트 설명이 아닙니다. 관리자에서 실제 내용으로 바꿔 주세요.\n\n기록하면 좋은 내용\n\n무엇을 만들었는지, 어떤 문제를 해결했는지, 내가 맡은 역할과 구현 과정, 배운 점을 정리해 보세요." }, demo: true)
        add_file(filename: "#{title.downcase.tr(' ', '-')}-sample.md", bytes: "# #{title}\n\n포트폴리오 사용법을 확인하기 위한 샘플 첨부파일입니다. 실제 자료로 교체해 주세요.\n",
          project_id: p['id'], label: "#{title} · 샘플 노트", public: true, demo: true) if index < 2
      end
    end

    def clear_demo
      removed = @store.update do |state|
        ids = state['projects'].values.select { |p| p['demo'] }.map { |p| p['id'] }
        ids.each { |id| state['projects'].delete(id) }
        records = state['files'].values.select { |f| f['demo'] || ids.include?(f['project_id']) }
        records.each { |f| remove_file_record(f['id'], state) }
        records
      end
      removed.each { |f| unlink_file(f) }
    end

    private

    def timestamp = Time.now.utc.iso8601(6)

    def text(input, key, max:, required: false)
      raw = input[key]
      raise ValidationError, "#{key}: 문자열을 입력해 주세요" unless raw.nil? || raw.is_a?(String)
      value = raw.to_s.dup.force_encoding(Encoding::UTF_8)
      raise ValidationError, "#{key}: 잘못된 문자 인코딩입니다" unless value.valid_encoding?
      value = value.strip
      raise ValidationError, "#{key}: 필수 항목을 입력해 주세요" if required && value.empty?
      raise ValidationError, "#{key}: #{max}자 이하로 입력해 주세요" if value.length > max
      raise ValidationError, "#{key}: 허용되지 않는 제어 문자가 있습니다" if value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
      value
    end

    def safe_url(value)
      value = value.to_s.strip
      return '' if value.empty?
      raise ValidationError, '링크는 1000자 이하의 HTTP 또는 HTTPS 주소로 입력해 주세요' if value.length > 1000 || value.match?(/[\s\x00-\x1f]/)
      uri = URI.parse(value)
      unless %w[http https].include?(uri.scheme) && uri.host && !uri.host.empty? && !uri.userinfo
        raise ValidationError, '링크는 아이디나 비밀번호가 없는 HTTP 또는 HTTPS 주소로 입력해 주세요'
      end
      value
    rescue URI::InvalidURIError
      raise ValidationError, '올바른 링크 주소를 입력해 주세요'
    end

    def tag_list(value)
      list = value.is_a?(Array) ? value : value.to_s.split(',')
      list = list.map { |tag| tag.to_s.strip }.reject(&:empty?).uniq
      raise ValidationError, '태그는 최대 8개, 각각 24자 이하로 입력해 주세요' if list.size > 8 || list.any? { |tag| tag.length > 24 || !tag.valid_encoding? || tag.match?(/[\x00-\x1f]/) }
      list
    end

    def validate_email!(value)
      unless value.match?(/\A[A-Za-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,63}\z/)
        raise ValidationError, '올바른 이메일 주소를 입력해 주세요'
      end
    end

    def public_in_state?(record, state)
      return false unless record && record['public']
      return true unless record['project_id']
      state['projects'][record['project_id']]&.fetch('status', nil) == 'published'
    end

    def remove_file_record(id, state)
      state['files'].delete(id)
      state['projects'].each_value { |p| p['cover_id'] = nil if p['cover_id'] == id }
      state['profile']['resume_id'] = '' if state['profile']['resume_id'] == id
    end

    def unlink_file(record)
      path = file_path(record)
      File.unlink(path) if File.file?(path)
    rescue SystemCallError => e
      # The record is already inaccessible. Report an orphan for local cleanup.
      warn "File cleanup failed for #{record['id']}: #{e.class}"
    end
  end
end
