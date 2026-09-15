# frozen_string_literal: true
require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/portfolio/repository'

class SupabasePersistenceTest < Minitest::Test
  Response = Struct.new(:code, :body)

  class FakePersistence
    attr_reader :states, :files

    def initialize(state: nil, unavailable: false, fail_on_save: false, fail_on_delete: false, commit_then_fail: false)
      @state = state
      @revision = state ? 1 : nil
      @states = []
      @files = {}
      @unavailable = unavailable
      @fail_on_save = fail_on_save
      @fail_on_delete = fail_on_delete
      @commit_then_fail = commit_then_fail
    end

    def restore_state
      raise Portfolio::PersistenceError, 'remote unavailable' if @unavailable
      @state && { 'state'=>deep_copy(@state), 'revision'=>@revision }
    end

    def save_state(state, expected_revision:)
      raise Portfolio::PersistenceError, 'remote unavailable' if @unavailable
      raise Portfolio::PersistenceError, 'remote write failed' if @fail_on_save
      if @revision != expected_revision
        raise Portfolio::PersistenceConflict, 'remote state changed; retry the request'
      end
      @state = deep_copy(state)
      @revision = @revision.to_i + 1
      @states << deep_copy(state)
      raise Portfolio::PersistenceTransportError, 'response lost after commit' if @commit_then_fail
      @revision
    end

    def upload_file(id, bytes)
      raise Portfolio::PersistenceError, 'remote unavailable' if @unavailable
      @files[id] = bytes.dup
    end

    def download_file(id)
      raise Portfolio::PersistenceError, 'remote unavailable' if @unavailable
      @files[id]
    end

    def delete_file(id)
      raise Portfolio::PersistenceError, 'remote unavailable' if @unavailable
      raise Portfolio::PersistenceError, 'remote delete failed' if @fail_on_delete
      @files.delete(id)
    end

    private

    def deep_copy(value)
      value && Marshal.load(Marshal.dump(value))
    end
  end

  def setup
    @first_dir = Dir.mktmpdir('supabase-persistence-first-')
    @second_dir = Dir.mktmpdir('supabase-persistence-second-')
  end

  def teardown
    FileUtils.remove_entry(@first_dir)
    FileUtils.remove_entry(@second_dir)
  end

  def test_state_and_uploaded_file_restore_into_a_new_repository
    remote = FakePersistence.new
    first = Portfolio::Repository.new(@first_dir, persistence: remote)
    first.setup_admin('owner', 'a-persistence-test-password!')
    record = first.save_entry({'title'=>'보존할 기록', 'body'=>'본문', 'page'=>'about', 'section'=>'strengths',
      'status'=>'published', 'level'=>''})
    file = first.add_file(filename:'자료.txt', bytes:'원격에도 남아야 합니다', project_id:record['id'], public:true)

    second = Portfolio::Repository.new(@second_dir, persistence: remote)
    assert second.authenticate('owner', 'a-persistence-test-password!')
    assert_equal record['title'], second.project(record['id'])['title']
    assert_equal '원격에도 남아야 합니다', File.binread(second.file_path(second.file(file['id']))).force_encoding('UTF-8')
    assert_operator remote.states.length, :>, 0
  end

  def test_stale_repository_cannot_overwrite_a_newer_remote_revision
    remote = FakePersistence.new
    first = Portfolio::Repository.new(@first_dir, persistence: remote)
    second = Portfolio::Repository.new(@second_dir, persistence: remote)
    first.setup_admin('owner', 'a-persistence-test-password!')
    assert_raises(Portfolio::PersistenceError) { second.setup_admin('other', 'a-persistence-test-password!') }
    assert first.authenticate('owner', 'a-persistence-test-password!')
  end

  def test_conflict_refreshes_stale_repository_before_the_next_edit
    remote = FakePersistence.new
    first = Portfolio::Repository.new(@first_dir, persistence: remote)
    second = Portfolio::Repository.new(@second_dir, persistence: remote)
    first.setup_admin('owner', 'a-persistence-test-password!')
    assert_raises(Portfolio::PersistenceError) { second.setup_admin('other', 'a-persistence-test-password!') }
    assert second.authenticate('owner', 'a-persistence-test-password!')
  end

  def test_project_delete_removes_attached_remote_files
    remote = FakePersistence.new
    repo = Portfolio::Repository.new(@first_dir, persistence: remote)
    project = repo.save_project({'title'=>'첨부 프로젝트', 'summary'=>'프로젝트 요약', 'body'=>'본문', 'category'=>'other', 'tags'=>'', 'status'=>'published'})
    file = repo.add_file(filename:'첨부.txt', bytes:'내용', project_id:project['id'])
    repo.delete_project(project['id'])
    refute remote.files.key?(file['id'])
  end

  def test_configured_remote_failure_does_not_fall_back_to_ephemeral_state
    remote = FakePersistence.new(unavailable: true)
    assert_raises(Portfolio::PersistenceError) do
      Portfolio::Repository.new(@first_dir, persistence: remote)
    end
  end

  def test_without_remote_persistence_local_repository_behavior_is_unchanged
    repo = Portfolio::Repository.new(@first_dir)
    repo.setup_admin('owner', 'a-local-test-password!')
    assert repo.authenticate('owner', 'a-local-test-password!')
  end

  def test_remote_file_is_removed_after_local_delete
    remote = FakePersistence.new
    repo = Portfolio::Repository.new(@first_dir, persistence: remote)
    file = repo.add_file(filename:'삭제할.txt', bytes:'지워져야 합니다')
    assert remote.files.key?(file['id'])
    repo.delete_file(file['id'])
    refute remote.files.key?(file['id'])
  end

  def test_failed_remote_state_write_does_not_commit_local_change
    remote = FakePersistence.new(fail_on_save: true)
    repo = Portfolio::Repository.new(@first_dir, persistence: remote)
    assert_raises(Portfolio::PersistenceError) { repo.setup_admin('owner', 'a-persistence-test-password!') }
    assert_nil repo.admin
  end

  def test_ambiguous_remote_state_response_keeps_blob_for_committed_metadata
    remote = FakePersistence.new(commit_then_fail: true)
    repo = Portfolio::Repository.new(@first_dir, persistence: remote)
    assert_raises(Portfolio::PersistenceTransportError) { repo.add_file(filename: '보존.txt', bytes: '내용') }
    file_id = remote.files.keys.fetch(0)
    restored = Portfolio::Repository.new(@second_dir, persistence: remote)
    assert restored.file(file_id)
    assert_equal '내용', File.binread(restored.file_path(restored.file(file_id))).force_encoding('UTF-8')
  end

  def test_corrupted_remote_file_is_rejected_during_restore
    remote = FakePersistence.new
    first = Portfolio::Repository.new(@first_dir, persistence: remote)
    file = first.add_file(filename:'무결성.txt', bytes:'원본')
    remote.files[file['id']] = '변조됨'
    assert_raises(Portfolio::PersistenceError) { Portfolio::Repository.new(@second_dir, persistence: remote) }
  end

  def test_remote_delete_failure_does_not_turn_a_committed_local_delete_into_an_error
    remote = FakePersistence.new(fail_on_delete: true)
    repo = Portfolio::Repository.new(@first_dir, persistence: remote)
    file = repo.add_file(filename:'정리.txt', bytes:'내용')
    repo.delete_file(file['id'])
    assert_nil repo.file(file['id'])
  end

  def test_supabase_environment_requires_both_url_and_service_key
    assert_nil Portfolio::SupabasePersistence.from_env({})
    assert_raises(Portfolio::PersistenceError) do
      Portfolio::SupabasePersistence.from_env('SUPABASE_URL'=>'https://example.supabase.co')
    end
    persistence = Portfolio::SupabasePersistence.from_env(
      'SUPABASE_URL'=>'https://example.supabase.co',
      'SUPABASE_SERVICE_ROLE_KEY'=>'secret-value', 'SUPABASE_BUCKET'=>'portfolio-data')
    assert_equal 'portfolio-data', persistence.bucket
  end

  def test_supabase_environment_accepts_current_secret_key_name
    persistence = Portfolio::SupabasePersistence.from_env(
      'SUPABASE_URL' => 'https://example.supabase.co', 'SUPABASE_SECRET_KEY' => 'sb_secret_test',
      'SUPABASE_BUCKET' => 'portfolio')
    assert_equal 'portfolio', persistence.bucket
  end

  def test_database_update_uses_conditional_revision_and_service_headers
    calls = []
    client = Portfolio::SupabaseDatabaseClient.new(url: 'https://example.supabase.co', service_role_key: 'secret',
      transport: lambda { |**request|
        calls << request
        Response.new('200', '[{"revision":2,"state":{}}]')
      })

    assert_equal 2, client.save_state({}, expected_revision: 1)
    call = calls.fetch(0)
    assert_equal Net::HTTP::Patch, call[:method]
    assert_includes call[:uri].request_uri, 'revision=eq.1'
    assert_equal 'Bearer secret', call[:headers]['Authorization']
    assert_equal 'secret', call[:headers]['apikey']
    assert_equal 'return=representation', call[:headers]['Prefer']
    payload = JSON.parse(call[:body])
    assert_equal 2, payload['revision']
  end

  def test_database_restore_accepts_a_single_row_response
    client = Portfolio::SupabaseDatabaseClient.new(url: 'https://example.supabase.co', service_role_key: 'secret',
      transport: ->(**) { Response.new('200', '{"revision":1,"state":{}}') })
    assert_equal({ 'state' => {}, 'revision' => 1 }, client.restore_state)
  end

  def test_database_update_rejects_empty_conditional_result
    client = Portfolio::SupabaseDatabaseClient.new(url: 'https://example.supabase.co', service_role_key: 'secret',
      transport: ->(**) { Response.new('200', '[]') })
    assert_raises(Portfolio::PersistenceError) { client.save_state({}, expected_revision: 4) }
  end

  def test_database_missing_table_does_not_look_like_an_empty_state
    client = Portfolio::SupabaseDatabaseClient.new(url: 'https://example.supabase.co', service_role_key: 'secret',
      transport: ->(**) { Response.new('404', '') })
    assert_raises(Portfolio::PersistenceError) { client.restore_state }
  end

  def test_current_secret_key_is_sent_as_an_api_key_without_jwt_bearer_header
    calls = []
    client = Portfolio::SupabaseDatabaseClient.new(url: 'https://example.supabase.co', service_role_key: 'sb_secret_test',
      transport: lambda { |**request|
        calls << request
        Response.new('200', '[]')
      })
    assert_nil client.restore_state
    assert_equal 'sb_secret_test', calls.fetch(0)[:headers]['apikey']
    refute calls.fetch(0)[:headers].key?('Authorization')
    assert_equal 'identity', calls.fetch(0)[:headers]['Accept-Encoding']
  end

  def test_non_json_database_response_reports_safe_response_details
    response = Response.new('200', '<html>gateway page</html>')
    response.define_singleton_method(:[]) { |name| name.to_s.downcase == 'content-type' ? 'text/html' : nil }
    client = Portfolio::SupabaseDatabaseClient.new(url: 'https://example.supabase.co', service_role_key: 'sb_secret_test',
      transport: ->(**) { response })

    error = assert_raises(Portfolio::PersistenceError) { client.restore_state }
    assert_includes error.message, 'HTTP 200'
    assert_includes error.message, 'text/html'
    refute_includes error.message, 'sb_secret_test'
  end

  def test_storage_client_uses_no_store_upload_and_cache_busted_download
    calls = []
    client = Portfolio::SupabaseObjectClient.new(url: 'https://example.supabase.co', service_role_key: 'secret', bucket: 'portfolio-data',
      transport: lambda { |**request|
        calls << request
        Response.new('200', 'bytes')
      })
    client.upload('files/a b.blob', 'bytes', content_type: 'text/plain')
    assert_equal 'bytes', client.download('files/a b.blob', cache_bust: true)
    assert_equal 'true', calls[0][:headers]['x-upsert']
    assert_equal 'no-store', calls[0][:headers]['cache-control']
    assert_equal 'no-cache', calls[1][:headers]['Cache-Control']
    assert_includes calls[1][:uri].query, 'v='
  end

  def test_storage_protocol_failure_is_treated_as_an_ambiguous_transport_error
    client = Portfolio::SupabaseObjectClient.new(url: 'https://example.supabase.co', service_role_key: 'secret', bucket: 'portfolio-data',
      transport: ->(**) { raise Net::ProtocolError, 'connection reset' })
    assert_raises(Portfolio::PersistenceTransportError) { client.upload('files/a.blob', 'bytes') }
  end
end
