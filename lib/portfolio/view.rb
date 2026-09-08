# frozen_string_literal: true
require 'erb'
require 'cgi'
require 'time'

module Portfolio
  class View
    ICONS = {
      'arrow' => '<path d="M5 12h14m-6-6 6 6-6 6"/>',
      'external' => '<path d="M7 17 17 7M7 7h10v10"/>',
      'download' => '<path d="M12 3v12m-5-5 5 5 5-5M5 16v4h14v-4"/>',
      'upload' => '<path d="M12 16V4m-5 5 5-5 5 5M5 16v4h14v-4"/>',
      'plus' => '<path d="M12 5v14M5 12h14"/>',
      'edit' => '<path d="m15 4 5 5M4 20l5-1L20 8a2 2 0 0 0-5-5L4 14v6Z"/>',
      'trash' => '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 10v7m4-7v7"/>',
      'file' => '<path d="M14 3H6a1 1 0 0 0-1 1v16h14V8l-5-5Zm0 0v5h5M8 12h8m-8 4h6"/>',
      'grid' => '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><rect x="14" y="14" width="6" height="6" rx="1"/>',
      'folder' => '<path d="M3 7V5h7l2 3h9v12H3V7Z"/>',
      'search' => '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
      'mail' => '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 6 9 7 9-7"/>',
      'lock' => '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3"/>',
      'logout' => '<path d="M9 4H4v16h5m5-13 5 5-5 5M8 12h11"/>',
      'check' => '<path d="m5 12 4 4L19 6"/>',
      'menu' => '<path d="M4 6h16M4 12h16M4 18h16"/>',
      'close' => '<path d="m6 6 12 12M6 18 18 6"/>',
      'code' => '<path d="m8 6-6 6 6 6m8-12 6 6-6 6m-3-15-2 18"/>',
      'user' => '<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
      'back' => '<path d="M19 12H5m6-6-6 6 6 6"/>',
      'eye' => '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
      'pin' => '<path d="M19 10c0 5-7 11-7 11S5 15 5 10a7 7 0 0 1 14 0Z"/><circle cx="12" cy="10" r="2"/>'
    }.freeze

    def initialize(config:, repository:, path:, authenticated:, csrf:, flash:, title:, data: {})
      @config, @repo, @path, @admin = config, repository, path, authenticated
      @profile = repository.profile
      @navigation = data.fetch(:navigation) { repository.notebook_navigation }
      @csrf, @flash, @title = csrf, flash, title
      @values = {}
      @error = nil
      data.each { |key, value| instance_variable_set("@#{key}", value) }
    end

    def render(name)
      @content = partial(name)
      partial('notebook/layout')
    end

    def partial(name, locals = {})
      # All template names are internal constants, never request parameters.
      path = File.join(@config.root, 'views', "#{name}.html.erb")
      scope = binding
      locals.each { |key, value| scope.local_variable_set(key, value) }
      ERB.new(File.read(path, encoding: 'UTF-8'), trim_mode: '-').result(scope)
    end

    def h(value) = CGI.escapeHTML(value.to_s)
    def icon(name) = "<svg class=\"icon\" width=\"20\" height=\"20\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\">#{ICONS.fetch(name)}</svg>"
    def csrf_field = "<input type=\"hidden\" name=\"_csrf\" value=\"#{h(@csrf)}\">"
    def field(key, fallback = '') = h(@values.fetch(key, fallback))
    def selected(value, expected) = value.to_s == expected.to_s ? 'selected' : ''
    def checked(value) = [true, '1', 'on'].include?(value) ? 'checked' : ''
    def category(value) = Repository::CATEGORIES.fetch(value, '기타')
    def q(value) = URI.encode_www_form_component(value.to_s)
    def active(path) = (@path == path || (path != '/admin' && path != '/' && @path.start_with?(path + '/'))) ? 'active' : ''

    def human_size(number)
      return format('%.1f MiB', number / (1024.0 * 1024)) if number >= 1024 * 1024
      return format('%.1f KiB', number / 1024.0) if number >= 1024
      "#{number} B"
    end

    def date(value)
      Time.iso8601(value.to_s).getlocal('+09:00').strftime('%Y.%m.%d')
    rescue ArgumentError
      ''
    end

    def paragraphs(value)
      value.to_s.split(/\n\s*\n/).map { |paragraph| "<p>#{h(paragraph).gsub("\n", '<br>')}</p>" }.join
    end

    def cover_file(project)
      file = @repo.file(project['cover_id'])
      file if file && Uploads::IMAGE_MIMES.include?(file['mime']) && (@admin || @repo.public_file?(file))
    end

    def public_resume
      file = @repo.file(@profile['resume_id'])
      file if file && file['mime'] == 'application/pdf' && @repo.public_file?(file)
    end

    def skills = @profile['skills'].to_s.split(',').map(&:strip).reject(&:empty?)
    def notebook_pages = @navigation
    def notebook_page(id) = Notebook.page(@navigation, id)
    def notebook_section(page_id, section_id) = Notebook.section(notebook_page(page_id), section_id)
    def page_href(page)
      @static ? (page == 'home' ? 'index.html' : "#{page}.html") : Notebook.path(page)
    end
    def asset_href(name) = @static ? "assets/#{name}" : "/assets/#{name}"
    def entry_href(record) = @static ? "entry-#{record['id']}.html" : "/entry/#{record['id']}"
    def attachment_href(record, preview: false)
      @static ? "files/#{record['id']}.#{record['extension']}" : "/files/#{record['id']}/#{preview ? 'preview' : 'download'}"
    end
    def attached_files(record)
      @repo.files.select { |f| f['project_id'] == record['id'] && (@admin || @repo.public_file?(f)) }
    end
    def entry_page(record) = Notebook.page_of(record, @navigation)
    def entry_section(record) = Notebook.section_of(record, @navigation)
    def notebook_records(page, section = nil)
      records = @repo.notebook_entries(page, section:section, public_only:!@admin)
      query = @filter_query.to_s.strip.downcase
      query.empty? ? records : records.select { |record| [record['title'],record['body'],*record['tags']].join(' ').downcase.include?(query) }
    end
    def current_page
      return @page_key if @page_key && notebook_page(@page_key)
      return 'home' if @path == '/' || @path == '/admin'
      match = notebook_pages.find { |page| Notebook.path(page['id']) == @path }
      match ? match['id'] : 'home'
    end
    def current_title = notebook_page(current_page)&.fetch('title', nil) || '홈'
    def editable? = @admin && !@static
    def free_preview? = !@static && @config.storage_dir.include?('portfolio-preview')
    def nav_count = @repo.messages.count { |message| !message['read'] }
  end
end
