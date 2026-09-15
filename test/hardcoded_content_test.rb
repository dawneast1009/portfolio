# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../app'

class HardcodedContentTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('portfolio-content-')
    @repo = Portfolio::Repository.new(@dir)
    @pdf = File.join(@dir, 'career-worksheet.pdf')
    File.binwrite(@pdf, "%PDF-1.4\n%seed\n%%EOF")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_seed_adds_profile_records_and_pdf
    @repo.setup_admin('owner', 'a-content-test-password!')
    @repo.seed_hardcoded_content!(pdf_path: @pdf)

    assert_equal 'dawneast', @repo.profile['display_name']
    assert_equal '나의 포트폴리오', @repo.profile['headline']
    assert_equal '나의 관심과 진로, 활동과 결과물을 한곳에 정리합니다.', @repo.profile['intro']
    assert_includes @repo.profile['bio'], '안녕하세요. 시스템 해킹을 주 분야로 공부 중인 dawneast입니다.'
    assert_includes @repo.profile['bio'], '기록해 놓은 포트폴리오 사이트입니다.'
    assert_equal 'https://velog.io/@dawneast/posts', @repo.profile['blog_url']
    assert_includes @repo.profile['bio'], 'CTF'
    assert @repo.projects.any? { |record| record['title'] == '수상 및 대회 실적' && record['notebook_page'] == 'activities' }
    assert @repo.projects.any? { |record| record['title'] == '동아리 활동' && record['notebook_section'] == 'club' }
    clubs = @repo.projects.find { |record| record['title'] == '동아리 활동' }
    assert_includes clubs['body'], '선린인터넷고등학교 121기'
    assert_includes clubs['body'], 'Null 동아리 2기'
    assert_includes clubs['body'], 'Phase 동아리 1기'
    refute_includes clubs['body'], 'th'
    awards = @repo.projects.find { |record| record['title'] == '수상 및 대회 실적' }
    assert_operator awards['body'].index('2026.09'), :<, awards['body'].index('2026.08')
    assert @repo.projects.any? { |record| record['title'] == '진로 학습지' && record['notebook_page'] == 'career' }
    assert @repo.projects.any? { |record| record['title'] == '포트폴리오 사이트' && record['notebook_page'] == 'career' }
    assert @repo.projects.any? do |record|
      record['title'] == '시스템 해킹 진로' && record['notebook_section'] == 'system_hacking'
    end
    portfolio = @repo.projects.find { |record| record['title'] == '포트폴리오 사이트' }
    assert_includes portfolio['body'], '성장 과정'
    refute_includes portfolio['body'], 'Supabase Database'
    pqc = @repo.projects.find { |record| record['title'] == 'PQC 암호 연구 (진행중)' }
    school_project = @repo.projects.find do |record|
      record['title'] == '선린 소수전공 4기 정보보안 프로젝트 (진행중)'
    end
    assert_equal 'personal', pqc['notebook_section']
    assert_equal '', pqc['body']
    assert_equal 'personal', school_project['notebook_section']
    assert_equal '', school_project['body']
    reversing = @repo.projects.find { |record| record['title'] == '선린 소수전공 3기 리버싱 심화 과정' }
    assert_equal 'activities', reversing['notebook_page']
    assert_equal 'advanced_study', reversing['notebook_section']
    activities = Portfolio::Notebook.page(@repo.notebook_navigation, 'activities')
    assert_equal '전공 심화 활동', Portfolio::Notebook.section(activities, 'advanced_study')['title']
    worksheet = @repo.files.find { |file| file['filename'] == Portfolio::HardcodedContent::PDF_FILENAME }
    refute_nil worksheet
    assert_equal true, worksheet['public']
    assert_equal 'application/pdf', worksheet['mime']
    assert_equal '진로 학습지', @repo.project(worksheet['project_id'])['title']
  end

  def test_seed_is_idempotent
    @repo.setup_admin('owner', 'a-content-test-password!')
    @repo.seed_hardcoded_content!(pdf_path: @pdf)
    first_counts = [@repo.projects.size, @repo.files.size]
    @repo.seed_hardcoded_content!(pdf_path: @pdf)
    assert_equal first_counts, [@repo.projects.size, @repo.files.size]
  end

  def test_seed_replaces_previous_combined_project
    @repo.setup_admin('owner', 'a-content-test-password!')
    @repo.save_entry({'title'=>'PQC 암호 연구 (진행중)','body'=>'선린 소수전공 4기 정보보안 프로젝트',
      'page'=>'projects','section'=>'personal','status'=>'published','level'=>''})
    @repo.save_entry({'title'=>'선린 소수전공 3기 리버싱 심화','body'=>'',
      'page'=>'projects','section'=>'personal','status'=>'published','level'=>''})

    @repo.seed_hardcoded_content!(pdf_path: @pdf)

    pqc_records = @repo.projects.select { |record| record['title'] == 'PQC 암호 연구 (진행중)' }
    assert_equal 1, pqc_records.length
    assert_equal '', pqc_records.first['body']
    assert @repo.projects.any? do |record|
      record['title'] == '선린 소수전공 4기 정보보안 프로젝트 (진행중)'
    end
    refute @repo.projects.any? { |record| record['title'] == '선린 소수전공 3기 리버싱 심화' }
    reversing = @repo.projects.find { |record| record['title'] == '선린 소수전공 3기 리버싱 심화 과정' }
    assert_equal 'activities', reversing['notebook_page']
    assert_equal 'advanced_study', reversing['notebook_section']
  end
end
