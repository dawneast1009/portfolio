# frozen_string_literal: true
module Portfolio
  module Notebook
    ICONS = %w[file user pin grid folder].freeze
    LEVELS = { ''=>'표시하지 않음', 'beginner'=>'입문', 'working'=>'활용', 'confident'=>'능숙' }.freeze
    MAX_PAGES = 20
    MAX_SECTIONS = 30

    freeze_tree = lambda do |value|
      case value
      when Hash
        value.each { |key, child| freeze_tree.call(key); freeze_tree.call(child) }
      when Array
        value.each { |child| freeze_tree.call(child) }
      end
      value.freeze
    end

    DEFAULT_NAVIGATION = freeze_tree.call([
      { 'id'=>'home', 'title'=>'홈', 'icon'=>'file',
        'description'=>'나를 소개하고 배움의 과정을 기록하는 공간',
        'sections'=>[{ 'id'=>'notes', 'title'=>'포트폴리오 소개' }] },
      { 'id'=>'about', 'title'=>'내 소개', 'icon'=>'user',
        'description'=>'내가 좋아하는 것과 중요하게 생각하는 것',
        'sections'=>[
          { 'id'=>'strengths', 'title'=>'강점' }, { 'id'=>'interests', 'title'=>'흥미' },
          { 'id'=>'values', 'title'=>'가치관' }, { 'id'=>'career_history', 'title'=>'진로활동 요약' }
        ] },
      { 'id'=>'career', 'title'=>'진로활동', 'icon'=>'pin',
        'description'=>'관심에서 시작해 나의 진로를 구체적으로 알아보기',
        'sections'=>[
          { 'id'=>'fields', 'title'=>'관심 분야' }, { 'id'=>'jobs', 'title'=>'관심 직업' },
          { 'id'=>'majors', 'title'=>'관심 학과' }
        ] },
      { 'id'=>'activities', 'title'=>'주요 활동 및 스킬', 'icon'=>'grid',
        'description'=>'참여한 활동과 그 과정에서 익힌 것들',
        'sections'=>[
          { 'id'=>'subject', 'title'=>'교과활동' }, { 'id'=>'club', 'title'=>'동아리활동' },
          { 'id'=>'career', 'title'=>'진로활동' }, { 'id'=>'tools', 'title'=>'사용 프로그램 및 숙련도' },
          { 'id'=>'strengths', 'title'=>'기타 강점' }
        ] },
      { 'id'=>'projects', 'title'=>'프로젝트', 'icon'=>'folder',
        'description'=>'읽고 탐구하고 만들어 낸 결과물을 모았습니다',
        'sections'=>[
          { 'id'=>'reading', 'title'=>'독서' }, { 'id'=>'report', 'title'=>'주제탐구보고서' },
          { 'id'=>'subject', 'title'=>'교과 프로젝트' }, { 'id'=>'career', 'title'=>'진로 프로젝트' },
          { 'id'=>'personal', 'title'=>'개인 프로젝트' }, { 'id'=>'outcomes', 'title'=>'작품 및 결과물' }
        ] }
    ])

    # Compatibility for templates while runtime consumers migrate to the stored tree.
    PAGES = DEFAULT_NAVIGATION.to_h do |page_record|
      sections = page_record['sections'].to_h { |item| [item['id'],item['title']] }.freeze
      [page_record['id'], { title:page_record['title'], icon:page_record['icon'],
        description:page_record['description'], sections:sections }.freeze]
    end.freeze

    module_function

    def default_navigation = Marshal.load(Marshal.dump(DEFAULT_NAVIGATION))
    def page(navigation, id) = navigation.find { |item| item['id'] == id.to_s }
    def section(page_record, id) = page_record && page_record['sections'].find { |item| item['id'] == id.to_s }
    def path(page_id) = page_id == 'home' ? '/' : "/#{page_id}"

    def page_of(record, navigation = DEFAULT_NAVIGATION)
      requested = record['notebook_page']
      return requested if page(navigation, requested)
      fallback = page(navigation, 'projects') || navigation.find { |item| !item['sections'].empty? } || navigation.first
      fallback&.fetch('id', nil)
    end

    def section_of(record, navigation = DEFAULT_NAVIGATION)
      page_record = page(navigation, page_of(record, navigation))
      return nil unless page_record
      requested = record['notebook_section']
      return requested if section(page_record, requested)
      return 'personal' if page_record['id'] == 'projects' && section(page_record, 'personal')
      page_record['sections'].first&.fetch('id')
    end

    def validate(page_id, section_id, level, navigation: DEFAULT_NAVIGATION)
      page_record = page(navigation, page_id)
      raise ValidationError, '목차에서 올바른 페이지를 선택해 주세요' unless page_record
      unless section(page_record, section_id)
        raise ValidationError, '선택한 페이지에 맞는 항목을 선택해 주세요'
      end
      unless LEVELS.key?(level.to_s)
        raise ValidationError, '숙련도는 입문, 활용, 능숙 중에서 선택해 주세요'
      end
      { 'notebook_page'=>page_record['id'], 'notebook_section'=>section_id.to_s, 'level'=>level.to_s }
    end
  end

  module NotebookRepository
    def notebook_navigation = Notebook.default_navigation

    def notebook_entries(page_id, section: nil, public_only: true)
      navigation = notebook_navigation
      projects.select do |record|
        Notebook.page_of(record, navigation) == page_id &&
          (!section || Notebook.section_of(record, navigation) == section) &&
          (!public_only || record['status'] == 'published')
      end.sort_by { |record| [record.fetch('created_at',''), record['id']] }
    end

    def save_entry(input, id: nil)
      navigation = notebook_navigation
      Notebook.validate(input['page'], input['section'], input['level'], navigation:navigation)
      old = id ? project(id) : nil
      raise NotFound, '기록을 찾을 수 없습니다' if id && !old
      title = text(input, 'title', max:100, required:true)
      body = text(input, 'body', max:30_000)
      values = (old || {}).merge('title'=>title, 'body'=>body,
        'summary'=>body.empty? ? title : body[0,280], 'category'=>old&.fetch('category','other') || 'other',
        'status'=>input['status'].to_s, 'notebook_page'=>input['page'], 'notebook_section'=>input['section'],
        'level'=>input['level'].to_s, 'live_url'=>input['link'].to_s)
      save_project(values, id:id)
    end
  end
end
