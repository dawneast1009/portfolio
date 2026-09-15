# frozen_string_literal: true

module Portfolio
  module HardcodedContent
    VERSION = 4
    PDF_FILENAME = 'CamScanner 2026. 09. 08. 12(1).pdf'

    PROFILE = {
      'display_name' => 'dawneast',
      'role' => '시스템 해킹·CTF 활동',
      'headline' => '나의 포트폴리오',
      'intro' => '나의 관심과 진로, 활동과 결과물을 한곳에 정리합니다.',
      'bio' => <<~TEXT.strip,
        안녕하세요. 시스템 해킹을 주 분야로 공부 중인 dawneast입니다.

        이 사이트는 제가 공부하고 여러 경험을 쌓으면서 참여한 CTF 대회와 동아리 활동, 진행한 프로젝트와 진로 학습 자료 등을 기록해 놓은 포트폴리오 사이트입니다.
      TEXT
      'skills' => '시스템 해킹, CTF, Linux, 바이너리 분석, Ruby, 문제 해결',
      'location' => 'Sunrin Internet High School',
      'blog_url' => 'https://velog.io/@dawneast/posts'
    }.freeze

    RECORDS = [
      {
        'title' => '시스템 해킹 진로', 'page' => 'career', 'section' => 'system_hacking',
        'category' => 'security', 'year' => '2026', 'tags' => '시스템 해킹, 진로, 정보보호',
        'body' => <<~TEXT.strip
          관심 분야
          시스템과 프로그램이 동작하는 원리를 이해하고 취약점을 찾아 해결하는 시스템 해킹에 관심이 있습니다.

          관심 직업
          보안 연구원과 취약점 분석가를 진로로 생각하고 있습니다.

          관심 학과
          정보보호학과와 컴퓨터공학과 등 보안과 시스템을 깊이 공부할 수 있는 학과에 관심이 있습니다.
        TEXT
      },
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
          공부하며 쌓은 경험과 결과물을 한눈에 볼 수 있도록 직접 만든 포트폴리오 사이트입니다.

          CTF 대회와 동아리 활동, 수상 기록, 진로 학습 자료를 주제별로 정리했습니다. 앞으로 새롭게 배우고 도전한 내용도 꾸준히 추가하며 저의 성장 과정을 기록해 나갈 예정입니다.
        TEXT
      },
      {
        'title' => 'PQC 암호 연구 (진행중)', 'page' => 'projects', 'section' => 'personal',
        'category' => 'research', 'year' => '2026', 'tags' => 'PQC, 암호학, 정보보안',
        'body' => <<~TEXT.strip
          선린 소수전공 4기 정보보안 프로젝트로 진행 중인 PQC 암호 연구입니다.

          양자컴퓨터 환경에서도 안전하게 사용할 수 있는 양자내성암호의 필요성과 원리를 공부하고 있습니다. 관련 알고리즘과 활용 사례를 조사하며 연구 내용을 정리하고 있습니다.
        TEXT
      }
    ].freeze
  end
end
