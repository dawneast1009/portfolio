# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../app'

class NotebookTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('school-notebook-')
    @repo = Portfolio::Repository.new(@dir)
  end
  def teardown = FileUtils.remove_entry(@dir)
  def entry(values = {})
    assert_respond_to @repo, :save_entry
    @repo.save_entry({ 'title'=>'학습 기록', 'body'=>'직접 작성한 내용', 'page'=>'about',
      'section'=>'strengths', 'status'=>'published', 'level'=>'' }.merge(values))
  end
  def test_five_exact_menus_and_school_categories
    assert defined?(Portfolio::Notebook), '학교 메뉴 구성이 구현되지 않았습니다'
    navigation = @repo.notebook_navigation
    assert_equal ['홈', '내 소개', '진로활동', '주요 활동 및 스킬', '프로젝트'], navigation.map { |page| page['title'] }
    projects = navigation.find { |page| page['id'] == 'projects' }
    assert_equal %w[reading report subject career personal outcomes], projects['sections'].map { |section| section['id'] }
  end
  def test_navigation_defaults_preserve_existing_ids_and_urls
    navigation = @repo.notebook_navigation
    assert_equal %w[home about career activities projects], navigation.map { |page| page['id'] }
    assert_equal %w[strengths interests values career_history], navigation[1]['sections'].map { |section| section['id'] }
    assert_equal '/', Portfolio::Notebook.path('home')
    assert_equal '/about', Portfolio::Notebook.path('about')
  end
  def test_navigation_page_and_section_changes_persist_with_stable_ids
    page = @repo.save_notebook_page({'title'=>'수상 기록', 'description'=>'받은 상을 정리합니다', 'icon'=>'folder'})
    section = @repo.save_notebook_section(page['id'], {'title'=>'교내 수상'})
    @repo.save_notebook_page({'title'=>'수상 및 자격', 'description'=>'수상과 자격증', 'icon'=>'file'}, id:page['id'])
    @repo.save_notebook_section(page['id'], {'title'=>'학교 수상'}, id:section['id'])
    reloaded = Portfolio::Repository.new(@dir)
    saved_page = Portfolio::Notebook.page(reloaded.notebook_navigation, page['id'])
    assert_equal '수상 및 자격', saved_page['title']
    assert_equal section['id'], saved_page['sections'].first['id']
    assert_equal '학교 수상', saved_page['sections'].first['title']
  end
  def test_navigation_reorders_and_deletes_only_empty_items
    page = @repo.save_notebook_page({'title'=>'수상', 'description'=>'', 'icon'=>'folder'})
    first = @repo.save_notebook_section(page['id'], {'title'=>'교내'})
    second = @repo.save_notebook_section(page['id'], {'title'=>'교외'})
    @repo.move_notebook_section(page['id'], second['id'], 'up')
    saved_page = Portfolio::Notebook.page(@repo.notebook_navigation, page['id'])
    assert_equal [second['id'], first['id']], saved_page['sections'].map { |item| item['id'] }
    @repo.move_notebook_page(page['id'], 'up')
    assert_equal page['id'], @repo.notebook_navigation[-2]['id']
    @repo.move_notebook_page('home', 'down')
    assert_equal 'home', @repo.notebook_navigation.first['id']
    @repo.delete_notebook_section(page['id'], first['id'])
    refute Portfolio::Notebook.section(Portfolio::Notebook.page(@repo.notebook_navigation, page['id']), first['id'])
    @repo.delete_notebook_page(page['id'])
    refute Portfolio::Notebook.page(@repo.notebook_navigation, page['id'])
  end
  def test_navigation_refuses_to_delete_items_with_records_or_home
    item = entry
    section_error = assert_raises(Portfolio::ValidationError) { @repo.delete_notebook_section('about', 'strengths') }
    assert_includes section_error.message, '기록'
    page_error = assert_raises(Portfolio::ValidationError) { @repo.delete_notebook_page('about') }
    assert_includes page_error.message, '기록'
    assert_raises(Portfolio::ValidationError) { @repo.delete_notebook_page('home') }
    assert_equal item['id'], @repo.notebook_entries('about', section:'strengths').first['id']
  end
  def test_navigation_renames_section_without_losing_its_records
    item = entry
    @repo.save_notebook_section('about', {'title'=>'나의 장점'}, id:'strengths')
    assert_equal item['id'], @repo.notebook_entries('about', section:'strengths').first['id']
    section = Portfolio::Notebook.section(Portfolio::Notebook.page(@repo.notebook_navigation, 'about'), 'strengths')
    assert_equal '나의 장점', section['title']
  end
  def test_navigation_validates_names_icons_parents_and_limits
    assert_raises(Portfolio::ValidationError) { @repo.save_notebook_page({'title'=>'', 'description'=>'', 'icon'=>'folder'}) }
    assert_raises(Portfolio::ValidationError) { @repo.save_notebook_page({'title'=>'기타', 'description'=>'', 'icon'=>'script'}) }
    assert_raises(Portfolio::NotFound) { @repo.save_notebook_section('missing-page', {'title'=>'항목'}) }
    15.times { |index| @repo.save_notebook_page({'title'=>"추가 #{index}", 'description'=>'', 'icon'=>'file'}) }
    assert_raises(Portfolio::ValidationError) { @repo.save_notebook_page({'title'=>'초과', 'description'=>'', 'icon'=>'file'}) }
  end
  def test_saves_and_filters_entries_by_page_and_section
    item = entry
    assert_equal 'about', item['notebook_page']
    assert_equal [item['id']], @repo.notebook_entries('about', section: 'strengths').map { |r| r['id'] }
    assert_empty @repo.notebook_entries('career')
    assert_equal item, Portfolio::Repository.new(@dir).project(item['id'])
  end
  def test_rejects_invalid_page_and_section
    assert_respond_to @repo, :save_entry
    assert_raises(Portfolio::ValidationError) { entry('page'=>'contact') }
    assert_raises(Portfolio::ValidationError) { entry('page'=>'career', 'section'=>'strengths') }
    assert_empty @repo.projects
  end
  def test_draft_files_remain_private_even_when_file_flag_is_public
    item = entry('status'=>'draft')
    file = @repo.add_file(filename:'비공개.txt', bytes:'secret', project_id:item['id'], public:true)
    assert_empty @repo.notebook_entries('about')
    assert_equal 1, @repo.notebook_entries('about', public_only:false).size
    refute @repo.public_file?(file)
  end
  def test_skill_level_and_update_preserve_identity
    item = entry('page'=>'activities','section'=>'tools','level'=>'working')
    revised = @repo.save_entry({ 'title'=>'VS Code', 'body'=>'직접 사용', 'page'=>'activities','section'=>'tools', 'level'=>'confident','status'=>'published' }, id:item['id'])
    assert_equal item['id'], revised['id']
    assert_equal 'confident', revised['level']
    assert_equal item['created_at'], revised['created_at']
    assert_raises(Portfolio::ValidationError) { entry('level'=>'expert!!!') }
  end
  def test_unsafe_link_rejected
    assert_respond_to @repo, :save_entry
    assert_raises(Portfolio::ValidationError) { entry('link'=>'javascript:alert(1)') }
  end
  def test_legacy_project_is_visible_in_personal_projects
    item = @repo.save_project({'title'=>'기존 자료','summary'=>'기존 소개','category'=>'development','status'=>'published'})
    assert_respond_to @repo, :notebook_entries
    assert_equal item['id'], @repo.notebook_entries('projects',section:'personal').first['id']
  end
  def test_school_document_extensions_and_bad_signatures
    zip = "PK\x03\x04".b + ("\0" * 40)
    %w[pptx docx xlsx hwpx].each do |ext|
      assert_includes Portfolio::Uploads::EXTENSIONS, ".#{ext}"
      assert @repo.add_file(filename:"과제.#{ext}",bytes:zip)
    end
    assert_includes Portfolio::Uploads::EXTENSIONS, '.hwp'
    assert @repo.add_file(filename:'보고서.hwp',bytes:"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1".b + ("\0" * 504))
    assert_raises(Portfolio::ValidationError) { @repo.add_file(filename:'가짜.pptx',bytes:'text') }
    assert_raises(Portfolio::ValidationError) { @repo.add_file(filename:'active.html',bytes:'<h1>x</h1>') }
  end
  def test_static_export_is_public_only_and_relative
    item = entry('title'=>'공개 기록')
    secret = entry('title'=>'PRIVATE_ENTRY_MARKER', 'status'=>'draft')
    pub = @repo.add_file(filename:'자료.txt',bytes:'public file',project_id:item['id'],public:true)
    @repo.add_file(filename:'숨김.txt',bytes:'PRIVATE_FILE_MARKER',project_id:item['id'],public:false)
    @repo.add_file(filename:'초안.txt',bytes:'DRAFT_FILE_MARKER',project_id:secret['id'],public:true)
    assert defined?(Portfolio::StaticExport), '정적 내보내기가 구현되지 않았습니다'
    cfg = Portfolio::Config.new(root:File.expand_path('..',__dir__),env:{'STORAGE_DIR'=>@dir})
    output = Portfolio::StaticExport.new(config:cfg, repository:@repo).entries
    %w[index.html about.html career.html activities.html projects.html .nojekyll].each { |name| assert output.key?(name), name }
    assert_equal 'public file', output["files/#{pub['id']}.txt"]
    text = output.values.map(&:b).join
    %w[PRIVATE_ENTRY_MARKER PRIVATE_FILE_MARKER DRAFT_FILE_MARKER portfolio.pstore _csrf].each { |secret_text| refute_includes text, secret_text }
    refute_match(/href="\/admin/, text)
    assert_includes output['index.html'], 'href="about.html"'
    assert_includes output['about.html'], "entry-#{item['id']}.html"
    refute_match(/(?:href|src)="\/(?!\/)/, output['about.html'])
  end
end
