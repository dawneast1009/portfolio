# frozen_string_literal: true
require 'pstore'
require 'fileutils'

module Portfolio
  class Store
    DEFAULT_PROFILE = {
      'display_name' => 'dawneast', 'role' => 'DEVELOPMENT / SECURITY / NOTES',
      'headline' => "만든 것과\n배운 것을 남깁니다",
      'intro' => '개발과 보안을 공부하며 작은 아이디어를 직접 구현합니다. 결과뿐 아니라 만들면서 배운 과정도 함께 기록합니다.',
      'bio' => "코드를 읽고 직접 만들어 보며 배우는 것을 좋아합니다.\n\n이곳에는 작업한 프로젝트와 공부한 내용을 차곡차곡 모읍니다. 각 프로젝트에서 무엇을 만들었고 어떤 문제를 해결했는지 기록합니다.",
      'skills' => 'Ruby, HTML / CSS, Python, Linux, CTF',
      'github_url' => '', 'blog_url' => '', 'contact_email' => '',
      'location' => '대한민국', 'resume_id' => '', 'status' => 'BUILDING & LEARNING'
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
