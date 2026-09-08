# frozen_string_literal: true
require_relative 'static_export'

module Portfolio
  # Reuse the original request/session/parser boundary; only school UI routes change.
  module NotebookRoutes
    NAVIGATION_ID = '[a-z0-9_-]{1,40}'
    LEGACY_NOTEBOOK_PATHS = %w[/about /career /activities /projects].freeze

    private
    def dispatch_get
      navigation = @repo.notebook_navigation
      page = navigation.find { |item| Notebook.path(item['id']) == @path }
      return render_notebook_page(page['id'], navigation:navigation) if page
      case @path
      when '/admin'
        render_notebook_page('home', navigation:navigation)
      when '/admin/share'
        render('notebook/share', title:'공유 및 제출', page_key:'home')
      when '/admin/navigation'
        render_navigation_manager
      when '/admin/export.zip'
        @res.body = StaticExport.new(config:@config, repository:@repo).archive
        @res['Content-Type'] = 'application/zip'
        @res['Content-Disposition'] = 'attachment; filename="portfolio-submission.zip"'
        @res['Content-Length'] = @res.body.bytesize.to_s
      when '/admin/notebook/new'
        selected_page = Notebook.page(navigation, @query['page']) || Notebook.page(navigation, 'projects') ||
          navigation.find { |item| !item['sections'].empty? }
        raise ValidationError, '기록을 추가하려면 목차에 하위 항목을 먼저 만들어 주세요' unless selected_page
        page_key = selected_page['id']
        section = @query['section'] || selected_page['sections'].first&.fetch('id')
        Notebook.validate(page_key, section, '', navigation:navigation)
        render_entry_form({'page'=>page_key,'section'=>section,'status'=>'draft','level'=>''}, navigation:navigation)
      when %r{\A/admin/notebook/(#{RequestContext::ID})/edit\z}
        record = @repo.project(Regexp.last_match(1))
        raise NotFound unless record
        render_entry_form(entry_form_values(record))
      when %r{\A/(?:entry|projects)/(#{RequestContext::ID})\z}
        record = @repo.project(Regexp.last_match(1))
        raise NotFound unless record && (record['status'] == 'published' || @authenticated)
        render('notebook/entry',title:record['title'],record:record,
          page_key:Notebook.page_of(record, navigation), navigation:navigation)
      when *LEGACY_NOTEBOOK_PATHS
        raise NotFound
      else
        super
      end
    end

    def dispatch_post
      case @path
      when '/admin/navigation/pages'
        navigation_action do
          @repo.save_notebook_page(@params)
          redirect('/admin/navigation', '새 상위 메뉴를 추가했습니다')
        end
      when %r{\A/admin/navigation/pages/(#{NAVIGATION_ID})\z}
        navigation_action do
          @repo.save_notebook_page(@params, id:Regexp.last_match(1))
          redirect('/admin/navigation', '상위 메뉴를 수정했습니다')
        end
      when %r{\A/admin/navigation/pages/(#{NAVIGATION_ID})/move\z}
        navigation_action do
          @repo.move_notebook_page(Regexp.last_match(1), @params['direction'])
          redirect('/admin/navigation', '상위 메뉴 순서를 변경했습니다')
        end
      when %r{\A/admin/navigation/pages/(#{NAVIGATION_ID})/delete\z}
        navigation_action do
          @repo.delete_notebook_page(Regexp.last_match(1))
          redirect('/admin/navigation', '상위 메뉴를 삭제했습니다')
        end
      when %r{\A/admin/navigation/pages/(#{NAVIGATION_ID})/sections\z}
        navigation_action do
          @repo.save_notebook_section(Regexp.last_match(1), @params)
          redirect('/admin/navigation', '새 하위 항목을 추가했습니다')
        end
      when %r{\A/admin/navigation/pages/(#{NAVIGATION_ID})/sections/(#{NAVIGATION_ID})\z}
        page_id, section_id = Regexp.last_match.captures
        navigation_action do
          @repo.save_notebook_section(page_id, @params, id:section_id)
          redirect('/admin/navigation', '하위 항목 이름을 수정했습니다')
        end
      when %r{\A/admin/navigation/pages/(#{NAVIGATION_ID})/sections/(#{NAVIGATION_ID})/move\z}
        page_id, section_id = Regexp.last_match.captures
        navigation_action do
          @repo.move_notebook_section(page_id, section_id, @params['direction'])
          redirect('/admin/navigation', '하위 항목 순서를 변경했습니다')
        end
      when %r{\A/admin/navigation/pages/(#{NAVIGATION_ID})/sections/(#{NAVIGATION_ID})/delete\z}
        page_id, section_id = Regexp.last_match.captures
        navigation_action do
          @repo.delete_notebook_section(page_id, section_id)
          redirect('/admin/navigation', '하위 항목을 삭제했습니다')
        end
      when '/admin/notebook' then save_notebook_entry
      when %r{\A/admin/notebook/(#{RequestContext::ID})\z}
        save_notebook_entry(Regexp.last_match(1))
      when %r{\A/admin/notebook/(#{RequestContext::ID})/delete\z}
        record = @repo.project(Regexp.last_match(1))
        raise NotFound unless record
        @repo.delete_project(record['id'])
        redirect(Notebook.path(Notebook.page_of(record, @repo.notebook_navigation)), '기록과 연결된 첨부파일을 삭제했습니다')
      when '/admin/notebook-upload'
        upload_notebook_file
      when %r{\A/admin/notebook/(#{RequestContext::ID})/files/(#{RequestContext::ID})/(delete|visibility)\z}
        parent_id, file_id, operation = Regexp.last_match.captures
        file = @repo.file(file_id)
        raise NotFound unless file && file['project_id'] == parent_id && @repo.project(parent_id)
        operation == 'delete' ? @repo.delete_file(file_id) : @repo.toggle_file_visibility(file_id)
        redirect("/admin/notebook/#{parent_id}/edit", '첨부파일 설정을 저장했습니다')
      else
        super
      end
    end

    def render_notebook_page(page_id, navigation: @repo.notebook_navigation)
      page = Notebook.page(navigation, page_id)
      raise NotFound unless page
      render('notebook/page', title:page['title'], page_key:page_id,
        filter_query:@query['q'].to_s, navigation:navigation)
    end

    def render_navigation_manager(error: nil, status: 200)
      render('admin/navigation', title:'목차 관리', page_key:'home', navigation:@repo.notebook_navigation,
        error:error, status:status)
    end

    def navigation_action
      yield
    rescue ValidationError => e
      render_navigation_manager(error:e.message, status:422)
    end

    def entry_form_values(record)
      navigation = @repo.notebook_navigation
      record.merge('page'=>Notebook.page_of(record, navigation),
        'section'=>Notebook.section_of(record, navigation), 'link'=>record['live_url'].to_s)
    end

    def render_entry_form(values, error: nil, status:200, navigation: @repo.notebook_navigation)
      selected_page = Notebook.page(navigation, values['page']) || Notebook.page(navigation, 'projects') || navigation.first
      raise NotFound unless selected_page
      key = selected_page['id']
      render('notebook/editor', title:values['id'] ? '기록 편집' : '새 기록',
        values:values, error:error, status:status, page_key:key,
        record:values['id'] ? @repo.project(values['id']) : nil, navigation:navigation)
    end

    def save_notebook_entry(id = nil)
      record = @repo.save_entry(@params,id:id)
      redirect("/admin/notebook/#{record['id']}/edit", '기록을 저장했습니다. 아래에서 파일을 붙일 수 있습니다')
    rescue ValidationError => e
      render_entry_form(@params.merge('id'=>id),error:e.message,status:422)
    end

    def upload_notebook_file
      record = @repo.project(@params['project_id'])
      raise NotFound unless record
      file = @params['file']
      raise ValidationError, '첨부할 파일을 선택해 주세요' unless file.is_a?(UploadPart) && !file.filename.to_s.empty?
      @repo.add_file(filename:file.filename,bytes:file.bytes,project_id:record['id'],
        label:@params['label'].to_s,public:@params['public']=='1')
      redirect("/admin/notebook/#{record['id']}/edit#attachments", '파일을 첨부했습니다')
    rescue ValidationError => e
      raise unless record
      render_entry_form(entry_form_values(record),error:e.message,status:422)
    end
  end
  RequestContext.prepend(NotebookRoutes)
end
