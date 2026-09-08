# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/portfolio/security'
require_relative '../lib/portfolio/repository'

class CoreTest < Minitest::Test
  PASSWORD = 'a-long-local-test-password!'

  def setup
    @dir = Dir.mktmpdir('portfolio-test-')
    @repo = Portfolio::Repository.new(@dir, max_upload_bytes: 1024 * 1024, max_storage_bytes: 2 * 1024 * 1024)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def project(**changes)
    @repo.save_project({ 'title' => 'A real project', 'summary' => 'A useful project description',
      'body' => 'Built with Ruby', 'category' => 'development', 'tags' => 'Ruby, HTML',
      'status' => 'published', 'featured' => '1' }.merge(changes.transform_keys(&:to_s)))
  end

  def upload(project_id: nil, name: 'notes.md', bytes: '# Notes\nHello', public: true)
    @repo.add_file(filename: name, bytes: bytes, project_id: project_id,
      label: 'Study notes', public: public)
  end

  def test_password_is_salted_and_not_plaintext
    one = Portfolio::Security.hash_password(PASSWORD)
    two = Portfolio::Security.hash_password(PASSWORD)
    refute_equal one, two
    refute_includes one.to_s, PASSWORD
    assert Portfolio::Security.verify_password(PASSWORD, one)
    refute Portfolio::Security.verify_password('wrong password', one)
  end

  def test_admin_requires_a_long_password
    assert_raises(Portfolio::ValidationError) { @repo.setup_admin('admin', 'short') }
    @repo.setup_admin('admin', PASSWORD)
    assert @repo.authenticate('admin', PASSWORD)
    refute @repo.authenticate('admin', 'wrong')
    refute @repo.authenticate('other', PASSWORD)
  end

  def test_project_survives_reopening_store
    p = project
    reopened = Portfolio::Repository.new(@dir)
    assert_equal p['title'], reopened.project(p['id'])['title']
  end

  def test_drafts_are_hidden_and_search_is_case_insensitive
    project(title: 'Ruby Portfolio')
    project(title: 'Private design', status: 'draft')
    assert_equal 1, @repo.public_projects.size
    assert_equal 1, @repo.public_projects(query: 'ruby').size
    assert_empty @repo.public_projects(query: 'private')
    assert_equal 1, @repo.public_projects(tag: 'HTML').size
    assert_empty @repo.public_projects(tag: 'Rust')
  end

  def test_project_validation_rejects_empty_title_and_unsafe_urls
    assert_raises(Portfolio::ValidationError) { project(title: '') }
    assert_raises(Portfolio::ValidationError) { project(repo_url: 'javascript:alert(1)') }
    assert_raises(Portfolio::ValidationError) { project(live_url: 'https://user:pass@example.com') }
  end

  def test_project_update_retains_id
    p = project
    updated = @repo.save_project(p.merge('title' => 'Changed'), id: p['id'])
    assert_equal p['id'], updated['id']
    assert_equal 'Changed', @repo.project(p['id'])['title']
  end

  def test_uploaded_filename_is_not_a_storage_path
    f = upload(name: '../../한글 notes.md')
    assert_equal '한글 notes.md', f['filename']
    assert File.file?(@repo.file_path(f))
    assert File.realpath(@repo.file_path(f)).start_with?(File.realpath(@dir) + File::SEPARATOR)
    refute_includes File.basename(@repo.file_path(f)), 'notes'
    assert_equal '# Notes\nHello', File.binread(@repo.file_path(f))
  end

  def test_upload_accepts_valid_pdf
    f = upload(name: 'report.pdf', bytes: "%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n")
    assert_equal 'application/pdf', f['mime']
  end

  def test_upload_rejects_executables_and_forged_pdf
    assert_raises(Portfolio::ValidationError) { upload(name: 'run.html', bytes: '<h1>no</h1>') }
    assert_raises(Portfolio::ValidationError) { upload(name: 'report.pdf', bytes: '<script>no</script>') }
    assert_raises(Portfolio::ValidationError) { upload(name: 'run.svg', bytes: '<svg/>') }
  end

  def test_upload_rejects_empty_binary_text_and_oversized_bytes
    assert_raises(Portfolio::ValidationError) { upload(bytes: '') }
    assert_raises(Portfolio::ValidationError) { upload(bytes: "binary\0data") }
    assert_raises(Portfolio::ValidationError) { upload(bytes: 'a' * (1024 * 1024 + 1)) }
    assert_empty @repo.files
  end

  def test_private_file_cannot_be_accessed_publicly
    f = upload(public: false)
    refute @repo.public_file?(f)
    assert_empty @repo.public_files
  end

  def test_draft_project_hides_even_public_attachments
    p = project(status: 'draft')
    f = upload(project_id: p['id'])
    refute @repo.public_file?(f)
    @repo.save_project(p.merge('status' => 'published'), id: p['id'])
    assert @repo.public_file?(@repo.file(f['id']))
    @repo.save_project(p.merge('status' => 'draft'), id: p['id'])
    assert_empty @repo.public_files
  end

  def test_missing_project_does_not_leave_orphan_bytes
    assert_raises(Portfolio::ValidationError) { upload(project_id: 'not-a-project') }
    assert_empty Dir.glob(File.join(@dir, 'uploads', '*'))
  end

  def test_quota_is_checked_before_committing
    upload(bytes: 'a' * (1024 * 1024))
    upload(bytes: 'b' * (1024 * 1024))
    assert_raises(Portfolio::ValidationError) { upload(bytes: 'c') }
    assert_equal 2, @repo.files.size
    assert_equal 2, Dir.glob(File.join(@dir, 'uploads', '*')).size
  end

  def test_project_delete_removes_attached_files
    p = project
    f = upload(project_id: p['id'])
    @repo.delete_project(p['id'])
    assert_nil @repo.project(p['id'])
    assert_nil @repo.file(f['id'])
    refute File.exist?(@repo.file_path(f))
  end

  def test_image_cover_must_belong_to_project
    p = project
    other = project(title: 'Other project')
    png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aU9sAAAAASUVORK5CYII='.unpack1('m0')
    f = upload(project_id: p['id'], name: 'cover.png', bytes: png)
    @repo.set_cover(f['id'])
    assert_equal f['id'], @repo.project(p['id'])['cover_id']
    assert_raises(Portfolio::ValidationError) do
      @repo.save_project(other.merge('cover_id' => f['id']), id: other['id'])
    end
  end

  def test_message_validation_and_read_state
    assert_raises(Portfolio::ValidationError) do
      @repo.add_message('name' => 'Reader', 'email' => 'bad', 'message' => 'Hello')
    end
    m = @repo.add_message('name' => 'Reader', 'email' => 'reader@example.com', 'message' => '<b>Hello</b>')
    assert_equal '<b>Hello</b>', @repo.messages.first['message']
    refute @repo.messages.first['read']
    @repo.mark_message_read(m['id'])
    assert @repo.messages.first['read']
    @repo.delete_message(m['id'])
    assert_empty @repo.messages
  end

  def test_profile_rejects_unsafe_link
    assert_raises(Portfolio::ValidationError) { @repo.update_profile('display_name' => 'dawneast', 'github_url' => 'data:text/html,hello') }
  end

  def test_resume_is_only_a_public_pdf
    f = upload
    assert_raises(Portfolio::ValidationError) { @repo.update_profile('resume_id' => f['id']) }
    p = project(status: 'draft')
    f = upload(project_id: p['id'], name: 'resume.pdf', bytes: "%PDF-1.7\n%%EOF")
    assert_raises(Portfolio::ValidationError) { @repo.update_profile('resume_id' => f['id']) }
  end

  def test_demo_is_explicit_and_can_be_removed_without_deleting_real_work
    @repo.seed_demo
    assert @repo.projects.all? { |p| p['demo'] }
    p = project
    @repo.clear_demo
    assert_equal [p['id']], @repo.projects.map { |item| item['id'] }
  end

  def test_session_rotation_invalidates_old_token
    sessions = Portfolio::Sessions.new
    token, session = sessions.create
    assert sessions.lookup(token)
    new_token, new_session = sessions.rotate(token, admin_version: 'v1')
    assert_nil sessions.lookup(token)
    assert_equal 'v1', new_session['admin_version']
    refute_equal session['csrf'], new_session['csrf']
    sessions.delete(new_token)
    assert_nil sessions.lookup(new_token)
  end

  def test_rate_limit_is_bounded
    limiter = Portfolio::RateLimiter.new
    3.times { assert limiter.allow?('key', limit: 3, window: 60) }
    refute limiter.allow?('key', limit: 3, window: 60)
    assert limiter.allow?('other', limit: 3, window: 60)
  end
end
