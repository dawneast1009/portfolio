# frozen_string_literal: true

module Portfolio
  module HardcodedContent
    VERSION = 2
    PDF_FILENAME = 'CamScanner 2026. 09. 08. 12(1).pdf'

    PROFILE = {
      'display_name' => 'dawneast',
      'role' => '시스템 해킹·CTF 활동',
      'headline' => '시스템 해킹을 배우며 성장하는 보안 인재',
      'intro' => '시스템 해킹을 주 분야로 CTF와 프로젝트에 도전하고, 직접 만들고 기록하며 성장하고 있습니다.',
      'bio' => <<~TEXT.strip,
        안녕하세요. 시스템 해킹을 주 분야로 공부하며 CTF와 다양한 프로젝트에 도전하고 있는 dawneast입니다.

        문제를 풀 때는 결과만 남기지 않고 풀이 과정과 배운 점을 기록하려고 합니다. Linux 환경과 바이너리, 메모리 구조를 이해하는 시스템 해킹을 중심으로 기초를 넓히고, 팀 활동과 대회를 통해 협업과 문제 해결 능력을 키우고 있습니다.

        이 포트폴리오는 수상 및 대회 기록, 동아리 활동, 진로 학습지와 직접 만든 포트폴리오 사이트를 한곳에 정리한 공간입니다.
      TEXT
      'skills' => '시스템 해킹, CTF, Linux, 바이너리 분석, Ruby, 문제 해결',
      'location' => 'Sunrin Internet High School',
      'blog_url' => 'https://velog.io/@dawneast/posts'
    }.freeze

    RECORDS = [
      {
        'title' => '수상 및 대회 실적', 'page' => 'activities', 'section' => 'awards',
        'category' => 'security', 'year' => '2026', 'tags' => 'CTF, 보안, 수상',
        'body' => <<~TEXT.strip
          2026.08 · CCE Finalist
          2026.09 · JBUCTF 2026 우수상
          2026.08 · gaslightCTF 2026 1위
          2026.08 · CyberGuardians CMX 본선 진출
          2026.08 · Universal CTF 2026 2위
          2026.07 · HackTheBox Cyber Apocalypse CTF 특별상
        TEXT
      },
      {
        'title' => '동아리 활동', 'page' => 'activities', 'section' => 'club',
        'category' => 'security', 'year' => '2026', 'tags' => '동아리, 보안, Sunrin',
        'body' => <<~TEXT.strip
          Sunrin Internet High School 121th
          Sunrin Null Club 2th
          Sunrin Phase Club 1th

          동아리 활동을 통해 보안 문제를 함께 분석하고, 풀이와 학습 내용을 나누며 꾸준히 실력을 쌓고 있습니다.
        TEXT
      },
      {
        'title' => '진로 학습지', 'page' => 'career', 'section' => 'worksheets',
        'category' => 'research', 'year' => '2026', 'tags' => '진로, 학습지, 보안',
        'body' => <<~TEXT.strip
          보안 분야에 대한 관심과 진로 계획을 정리한 학습지입니다.

          CTF와 프로젝트 경험을 바탕으로 보안 분야에서 필요한 역량을 찾아보고, 앞으로 공부할 내용과 실천 계획을 정리했습니다. 첨부한 PDF에서 학습지 원본을 확인할 수 있습니다.
        TEXT
      },
      {
        'title' => '포트폴리오 사이트', 'page' => 'career', 'section' => 'portfolio',
        'category' => 'development', 'year' => '2026', 'tags' => 'Ruby, Supabase, 포트폴리오',
        'body' => <<~TEXT.strip
          나의 활동과 결과물을 직접 정리하고 공개하기 위해 만든 포트폴리오 사이트입니다.

          Ruby 기반 웹 애플리케이션으로 프로필과 기록을 관리하고, Supabase Database와 Storage를 연결해 재시작 이후에도 내용과 첨부파일이 유지되도록 구성했습니다. 관리자 화면에서 상위 메뉴, 하위 항목, 진로 기록과 프로젝트를 직접 수정할 수 있습니다.
        TEXT
      }
    ].freeze
  end
end
