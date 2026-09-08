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
    assert_equal ['홈', '내 소개', '진로활동', '주요 활동 및 스킬', '프로젝트'], Portfolio::Notebook::PAGES.values.map { |v| v[:title] }
    assert_equal %w[reading report subject career personal outcomes], Portfolio::Notebook::PAGES['projects'][:sections].keys
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
