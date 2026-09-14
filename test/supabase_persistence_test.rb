# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/portfolio/repository'

class SupabasePersistenceTest < Minitest::Test
  class FakePersistence
    attr_reader :states, :files

    def initialize(state: nil, unavailable: false)
      @state = state
      @states = []
      @files = {}
      @unavailable = unavailable
    end

    def restore_state
      raise Portfolio::PersistenceError, 'remote unavailable' if @unavailable
      deep_copy(@state)
    end

    def save_state(state)
      raise Portfolio::PersistenceError, 'remote unavailable' if @unavailable
      @state = deep_copy(state)
      @states << deep_copy(state)
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
end
