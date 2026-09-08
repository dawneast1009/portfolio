# frozen_string_literal: true
require_relative 'static_export'

module Portfolio
  # Reuse the original request/session/parser boundary; only school UI routes change.
  module NotebookRoutes
    private
    def dispatch_get
      page = Notebook::PAGES.keys.find { |key| Notebook.path(key) == @path }
      return render_notebook_page(page) if page
      case @path
      when '/admin'
        render_notebook_page('home')
      when '/admin/share'
        render('notebook/share', title:'공유 및 제출', page_key:'home')
      when '/admin/export.zip'
        @res.body = StaticExport.new(config:@config, repository:@repo).archive
        @res['Content-Type'] = 'application/zip'
        @res['Content-Disposition'] = 'attachment; filename="portfolio-submission.zip"'
        @res['Content-Length'] = @res.body.bytesize.to_s
      when '/admin/notebook/new'
        page_key = Notebook::PAGES.key?(@query['page']) ? @query['page'] : 'projects'
        section = @query['section'] || Notebook::PAGES[page_key][:sections].keys.first
        Notebook.validate(page_key, section, '')
        render_entry_form({'page'=>page_key,'section'=>section,'status'=>'draft','level'=>''})
      when %r{\A/admin/notebook/(#{RequestContext::ID})/edit\z}
        record = @repo.project(Regexp.last_match(1))
        raise NotFound unless record
        render_entry_form(entry_form_values(record))
      when %r{\A/(?:entry|projects)/(#{RequestContext::ID})\z}
        record = @repo.project(Regexp.last_match(1))
        raise NotFound unless record && (record['status'] == 'published' || @authenticated)
        render('notebook/entry',title:record['title'],record:record,page_key:Notebook.page_of(record))
      else
        super
      end
    end

    def dispatch_post
      case @path
      when '/admin/notebook' then save_notebook_entry
      when %r{\A/admin/notebook/(#{RequestContext::ID})\z}
        save_notebook_entry(Regexp.last_match(1))
      when %r{\A/admin/notebook/(#{RequestContext::ID})/delete\z}
        record = @repo.project(Regexp.last_match(1))
        raise NotFound unless record
        @repo.delete_project(record['id'])
        redirect(Notebook.path(Notebook.page_of(record)), '기록과 연결된 첨부파일을 삭제했습니다')
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

    def render_notebook_page(page)
      render('notebook/page', title:Notebook::PAGES.fetch(page)[:title], page_key:page, filter_query:@query['q'].to_s)
    end

    def entry_form_values(record)
      record.merge('page'=>Notebook.page_of(record),'section'=>Notebook.section_of(record), 'link'=>record['live_url'].to_s)
    end

    def render_entry_form(values, error: nil, status:200)
      key = Notebook::PAGES.key?(values['page']) ? values['page'] : 'projects'
      render('notebook/editor', title:values['id'] ? '기록 편집' : '새 기록',
        values:values, error:error, status:status, page_key:key, record:values['id'] ? @repo.project(values['id']) : nil)
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
