# frozen_string_literal: true
require 'pstore'
require 'fileutils'

module Portfolio
  class Store
    DEFAULT_PROFILE = {
      'display_name' => 'dawneast', 'role' => '나의 성장 기록',
      'headline' => '나의 포트폴리오',
      'intro' => '나의 관심과 진로, 활동과 결과물을 한곳에 정리합니다.',
      'bio' => '',
      'skills' => '',
      'github_url' => '', 'blog_url' => '', 'contact_email' => '',
      'location' => '', 'resume_id' => '', 'status' => ''
    }.freeze

    def initialize(directory)
      FileUtils.mkdir_p(directory, mode: 0o700)
      @path = File.join(directory, 'portfolio.pstore')
      @database = PStore.new(@path, true)
      @database.ultra_safe = true
      @database.transaction do
        @database[:state] ||= { 'schema_version' => 1, 'profile' => DEFAULT_PROFILE.dup,
          'admin' => nil, 'projects' => {}, 'files' => {}, 'messages' => {} }
        raise 'Unsupported storage schema' unless @database[:state]['schema_version'] == 1
      end
      File.chmod(0o600, @path)
    end

    def read
      @database.transaction(true) do
        # Only locally-created, trusted application state is deserialized.
        Marshal.load(Marshal.dump(@database[:state]))
      end
    end

    def update
      @database.transaction do
        state = @database[:state]
        result = yield(state)
        @database[:state] = state
        result
      end
    end
  end
end
