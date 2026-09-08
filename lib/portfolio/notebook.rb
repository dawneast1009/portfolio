# frozen_string_literal: true
module Portfolio
  # Navigation and section IDs are fixed application data, not user-supplied paths.
  module Notebook
    PAGES = {
      'home' => { title: '홈', icon: 'file', description: '나를 소개하고 배움의 과정을 기록하는 공간', sections: { 'notes'=>'포트폴리오 소개' } },
      'about' => { title: '내 소개', icon: 'user', description: '내가 좋아하는 것과 중요하게 생각하는 것', sections: {
        'strengths'=>'강점', 'interests'=>'흥미', 'values'=>'가치관', 'career_history'=>'진로활동 요약' } },
      'career' => { title: '진로활동', icon: 'pin', description: '관심에서 시작해 나의 진로를 구체적으로 알아보기', sections: {
        'fields'=>'관심 분야', 'jobs'=>'관심 직업', 'majors'=>'관심 학과' } },
      'activities' => { title: '주요 활동 및 스킬', icon: 'grid', description: '참여한 활동과 그 과정에서 익힌 것들', sections: {
        'subject'=>'교과활동', 'club'=>'동아리활동', 'career'=>'진로활동', 'tools'=>'사용 프로그램 및 숙련도', 'strengths'=>'기타 강점' } },
      'projects' => { title: '프로젝트', icon: 'folder', description: '읽고 탐구하고 만들어 낸 결과물을 모았습니다', sections: {
        'reading'=>'독서', 'report'=>'주제탐구보고서', 'subject'=>'교과 프로젝트', 'career'=>'진로 프로젝트', 'personal'=>'개인 프로젝트', 'outcomes'=>'작품 및 결과물' } }
    }.freeze
    LEVELS = { ''=>'표시하지 않음', 'beginner'=>'입문', 'working'=>'활용', 'confident'=>'능숙' }.freeze
    module_function
    def page_of(record) = PAGES.key?(record['notebook_page']) ? record['notebook_page'] : 'projects'
    def section_of(record)
      page = page_of(record)
      section = record['notebook_section']
      return section if PAGES[page][:sections].key?(section)
      page == 'projects' ? 'personal' : PAGES[page][:sections].keys.first
    end
    def path(page) = page == 'home' ? '/' : "/#{page}"
    def validate(page, section, level)
      raise ValidationError, '목차에서 올바른 페이지를 선택해 주세요' unless PAGES.key?(page.to_s)
      raise ValidationError, '선택한 페이지에 맞는 항목을 선택해 주세요' unless PAGES[page.to_s][:sections].key?(section.to_s)
      raise ValidationError, '숙련도는 입문, 활용, 능숙 중에서 선택해 주세요' unless LEVELS.key?(level.to_s)
      { 'notebook_page'=>page.to_s, 'notebook_section'=>section.to_s, 'level'=>level.to_s }
    end
  end

  module NotebookRepository
    def notebook_entries(page, section: nil, public_only: true)
      projects.select do |record|
        Notebook.page_of(record) == page && (!section || Notebook.section_of(record) == section) &&
          (!public_only || record['status'] == 'published')
      end.sort_by { |record| [record.fetch('created_at',''), record['id']] }
    end

    def save_entry(input, id: nil)
      Notebook.validate(input['page'], input['section'], input['level'])
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
