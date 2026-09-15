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
    assert_includes @repo.profile['intro'], '시스템 해킹'
    assert_equal 'https://velog.io/@dawneast/posts', @repo.profile['blog_url']
    assert_includes @repo.profile['bio'], 'CTF'
    assert @repo.projects.any? { |record| record['title'] == '수상 및 대회 실적' && record['notebook_page'] == 'activities' }
    assert @repo.projects.any? { |record| record['title'] == '동아리 활동' && record['notebook_section'] == 'club' }
    assert @repo.projects.any? { |record| record['title'] == '진로 학습지' && record['notebook_page'] == 'career' }
    assert @repo.projects.any? { |record| record['title'] == '포트폴리오 사이트' && record['notebook_page'] == 'career' }
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
end
