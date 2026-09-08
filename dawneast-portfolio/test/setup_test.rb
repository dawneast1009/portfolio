# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require_relative '../lib/portfolio/repository'

class SetupTest < Minitest::Test
  PASSWORD = 'a-unique-test-setup-password!'
  ROOT = File.expand_path('..', __dir__)

  def setup
    @directory = Dir.mktmpdir('portfolio-setup-')
  end

  def teardown = FileUtils.remove_entry(@directory)

  def run_setup(*args, input: '')
    Open3.capture3({ 'STORAGE_DIR' => @directory, 'APP_ENV' => 'test' },
      RbConfig.ruby, File.join(ROOT, 'bin/setup'), *args, stdin_data: input)
  end

  def test_setup_creates_account_and_explicit_demo_without_echoing_password
    out, err, status = run_setup('--username', 'owner', '--demo', '--password-stdin', input: "#{PASSWORD}\n#{PASSWORD}\n")
    assert status.success?, err
    refute_includes out + err, PASSWORD
    repo = Portfolio::Repository.new(@directory)
    assert repo.authenticate('owner', PASSWORD)
    assert_equal 3, repo.projects.count { |p| p['demo'] }
  end

  def test_rerun_does_not_overwrite_an_existing_password
    repo = Portfolio::Repository.new(@directory)
    repo.setup_admin('owner', PASSWORD)
    _out, err, status = run_setup('--password-stdin', input: "other-password-value\nother-password-value\n")
    assert status.success?, err
    assert repo.authenticate('owner', PASSWORD)
  end

  def test_short_or_mismatched_password_is_rejected
    _out, _err, status = run_setup('--password-stdin', input: "short\nshort\n")
    refute status.success?
    assert_nil Portfolio::Repository.new(@directory).admin
    _out, _err, status = run_setup('--password-stdin', input: "#{PASSWORD}\nnot-matching-password\n")
    refute status.success?
    assert_nil Portfolio::Repository.new(@directory).admin
  end

  def test_reset_keeps_projects_and_replaces_password
    repo = Portfolio::Repository.new(@directory)
    repo.setup_admin('owner', PASSWORD)
    repo.seed_demo
    replacement = 'the-replacement-password-for-test!'
    _out, err, status = run_setup('--reset-password', '--password-stdin', input: "#{replacement}\n#{replacement}\n")
    assert status.success?, err
    assert repo.authenticate('owner', replacement)
    refute repo.authenticate('owner', PASSWORD)
    assert_equal 3, repo.projects.size
  end

  def test_noninteractive_input_requires_an_explicit_flag
    _out, _err, status = run_setup(input: "#{PASSWORD}\n#{PASSWORD}\n")
    refute status.success?
    assert_nil Portfolio::Repository.new(@directory).admin
  end
end
