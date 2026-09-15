# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require_relative '../lib/portfolio/repository'
implementation = File.expand_path('../lib/portfolio/deployment.rb', __dir__)
require implementation if File.file?(implementation)

class DeploymentTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  PASSWORD = 'deployment-test-password-not-for-production!'

  def setup
    @directory = Dir.mktmpdir('portfolio-deployment-')
    @env = { 'RENDER_EXTERNAL_URL' => 'https://portfolio-test.onrender.com',
      'STORAGE_DIR' => @directory, 'ADMIN_USERNAME' => 'owner', 'ADMIN_PASSWORD' => PASSWORD }
    assert defined?(Portfolio::Deployment), 'Deployment bootstrap has not been implemented'
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def prepare = Portfolio::Deployment.prepare!(root: ROOT, env: @env)
  def repository = Portfolio::Repository.new(@directory)

  def test_first_boot_creates_account_and_uses_render_origin
    settings = prepare
    assert_equal 'production', settings.environment
    assert_equal '0.0.0.0', settings.bind
    assert_equal 10_000, settings.port
    assert_equal @env['RENDER_EXTERNAL_URL'], settings.app_url
    assert_equal ['portfolio-test.onrender.com'], settings.allowed_hosts
    assert repository.authenticate('owner', PASSWORD)
    refute @env.key?('ADMIN_PASSWORD')
    titles = repository.projects.map { |project| project['title'] }
    assert_includes titles, '동아리 활동'
    assert_includes titles, '수상 및 대회 실적'
    assert_equal 4, repository.projects.length
  end

  def test_restart_preserves_account_and_does_not_need_bootstrap_secret
    prepare
    assert prepare
    assert repository.authenticate('owner', PASSWORD)
  end

  def test_restart_never_resets_password_from_environment
    prepare
    @env['ADMIN_PASSWORD'] = 'different-deployment-password!'
    prepare
    assert repository.authenticate('owner', PASSWORD)
    refute repository.authenticate('owner', 'different-deployment-password!')
    refute @env.key?('ADMIN_PASSWORD')
  end

  def test_supabase_boot_failure_still_serves_hardcoded_portfolio
    @env['SUPABASE_URL'] = 'https://example.supabase.co'
    @env['SUPABASE_SERVICE_ROLE_KEY'] = 'sb_secret_test'

    settings = nil
    _stdout, stderr = capture_io do
      Portfolio::SupabasePersistence.stub(:from_env, ->(*) { raise Portfolio::PersistenceError, 'invalid response' }) do
        settings = prepare
      end
    end

    assert_equal 'production', settings.environment
    assert_includes repository.projects.map { |project| project['title'] }, '수상 및 대회 실적'
    assert_includes stderr, 'Supabase 저장을 사용할 수 없어 기본 콘텐츠로 실행합니다'
    refute @env.key?('SUPABASE_URL')
    refute @env.key?('SUPABASE_SERVICE_ROLE_KEY')
  end

  def test_new_storage_without_password_fails_closed
    @env.delete('ADMIN_PASSWORD')
    assert_raises(ArgumentError) { prepare }
    assert_nil repository.admin
  end

  def test_short_password_is_rejected_and_removed
    @env['ADMIN_PASSWORD'] = 'short'
    assert_raises(Portfolio::ValidationError) { prepare }
    assert_nil repository.admin
    refute @env.key?('ADMIN_PASSWORD')
  end

  def test_custom_https_origin_and_platform_port_are_respected
    @env['APP_URL'] = 'https://portfolio.example.com'
    @env['PORT'] = '12000'
    settings = prepare
    assert_equal 'https://portfolio.example.com', settings.app_url
    assert_equal 12_000, settings.port
  end

  def test_invalid_or_missing_origin_is_rejected_before_creating_account
    @env['APP_URL'] = 'http://portfolio.example.com'
    assert_raises(ArgumentError) { prepare }
    assert_nil repository.admin
    refute @env.key?('ADMIN_PASSWORD')
  end

  def test_demo_is_only_seeded_on_first_account_creation
    @env['SEED_DEMO'] = 'true'
    prepare
    assert_equal 7, repository.projects.length
    seeded_titles = ['동아리 활동', '수상 및 대회 실적', '진로 학습지', '포트폴리오 사이트']
    repository.projects.reject { |p| seeded_titles.include?(p['title']) }.each do |p|
      repository.delete_project(p['id'])
    end
    prepare
    assert_equal 4, repository.projects.length
  end

  def test_deployment_requires_explicit_storage_path
    @env.delete('STORAGE_DIR')
    assert_raises(ArgumentError) { prepare }
    refute @env.key?('ADMIN_PASSWORD')
  end

  def test_default_blueprint_is_free_and_cannot_create_a_paid_disk
    service = YAML.safe_load_file(File.join(ROOT, 'render.yaml')).fetch('services').first
    assert_equal 'free', service.fetch('plan')
    assert_equal 'ruby', service.fetch('runtime')
    refute service.key?('disk')
    assert_equal 1, service.fetch('numInstances')
    env = service.fetch('envVars').to_h { |v| [v.fetch('key'), v] }
    assert_equal '/tmp/portfolio-preview', env.fetch('STORAGE_DIR').fetch('value')
    assert_equal 'false', env.fetch('SEED_DEMO').fetch('value')
    assert_equal false, env.fetch('ADMIN_PASSWORD').fetch('sync')
    assert_equal 'bundle exec ruby bin/render-start', service.fetch('startCommand')
  end

  def test_free_blueprint_is_explicitly_a_nonpersistent_preview
    service = YAML.safe_load_file(File.join(ROOT, 'render-free.yaml')).fetch('services').first
    assert_equal 'free', service.fetch('plan')
    refute service.key?('disk')
    assert_includes service.fetch('name'), 'preview'
    env = service.fetch('envVars').to_h { |v| [v.fetch('key'), v] }
    assert_equal '/tmp/portfolio-preview', env.fetch('STORAGE_DIR').fetch('value')
  end

  def test_free_blueprint_exposes_optional_supabase_persistence_secrets
    service = YAML.safe_load_file(File.join(ROOT, 'render-free.yaml')).fetch('services').first
    env = service.fetch('envVars').to_h { |v| [v.fetch('key'), v] }
    assert_equal false, env.fetch('SUPABASE_URL').fetch('sync')
    assert_equal false, env.fetch('SUPABASE_SERVICE_ROLE_KEY').fetch('sync')
    assert_equal 'portfolio', env.fetch('SUPABASE_BUCKET').fetch('value')
    setup = File.read(File.join(ROOT, 'SUPABASE_SETUP.md'), encoding: 'UTF-8')
    assert_includes setup, 'SUPABASE_SERVICE_ROLE_KEY'
    assert_includes setup, 'ruby bin/supabase-migrate'
    assert_includes setup, 'Public bucket을 끕니다'
  end
end
