# 공개 배포 전 확인 사항

## 실행 경로

로컬 확인: `ruby app.rb`

공개 배포 구성: `config.ru` + `config/puma.rb` + HTTPS 리버스 프록시

WEBrick 공식 README는 테스트와 로컬 개발 용도로 범위를 명시합니다. 따라서 이 프로젝트의 `app.rb`는 production 모드 및 외부 바인딩을 거부합니다. 공개 환경에서 단순히 BIND를 0.0.0.0으로 바꾸고 개발 서버를 열지 마세요.

Puma 실행 경로에서는 Puma가 HTTP 연결을 처리합니다. WEBrick 서버는 시작하지 않으며, WEBrick 의존성은 앱 내부의 크기 제한된 multipart와 쿠키 파싱 유틸리티에도 사용됩니다. 업로드 검증을 파일 시그니처 확인만으로 완전하다고 간주하지 마세요.

## 설치와 설정

Ruby 3.3/3.4의 최신 패치 환경과 빌드 도구를 준비하고, 프로젝트 폴더에서 의존성을 설치하세요. Puma의 네이티브 확장 빌드에 필요한 도구는 운영체제에 따라 다릅니다.

```bash
gem install bundler
bundle install
bundle exec ruby bin/setup
bundle exec ruby bin/test
```

이미 로컬에서 만든 계정과 내용을 옮기는 경우 서버를 정지한 상태에서 기존 저장소 전체를 옮긴 뒤 권한을 확인하세요. 새 setup으로 기존 데이터를 덮어쓸 필요가 없습니다.

`.env` 설정 예시에서 도메인과 저장 경로는 실제 값으로 바꾸세요.

```dotenv
APP_ENV=production
BIND=127.0.0.1
PORT=4567
APP_URL=https://portfolio.example.com
STORAGE_DIR=/var/lib/dawneast-portfolio
MAX_UPLOAD_MB=10
MAX_STORAGE_MB=500
```

```bash
bundle exec puma -C config/puma.rb
```

Puma에는 단일 프로세스, 최대 8개 스레드, 연결 타임아웃, 본문 크기 제한을 설정했습니다. 세션과 rate limit이 메모리에 있으므로 **workers 또는 replica 수를 늘리지 마세요**. 여러 서버로 확장하려면 세션/요청 제한 저장소와 데이터베이스 구조를 먼저 변경해야 합니다.

이 작업 환경에는 Puma/Rack gem을 새로 설치할 네트워크가 없어 실제 Puma 프로세스 시작과 TLS 연동은 검증하지 못했습니다. Rack 어댑터에 동일한 폼·인증·업로드 테스트를 적용한 결과와, 실제 Puma/프록시 환경 검증은 구분해야 합니다.

## 프록시와 외부 공개

운영 서버의 검증된 HTTPS 리버스 프록시에서 외부 TLS를 종료하고 `127.0.0.1:4567`로 전달하세요. Host 헤더는 APP_URL에 지정한 도메인으로 유지해야 합니다. 앱은 프록시가 넘긴 임의의 X-Forwarded-For를 인증이나 클라이언트 식별의 근거로 신뢰하지 않습니다.

프록시에서 적용할 사항:

- 요청 본문 크기 제한: 기본 업로드 10 MiB일 때 multipart 여유분을 포함해 12 MiB
- 연결·본문 수신 타임아웃과 로그인/문의 경로 요청 횟수 제한
- HTTP를 HTTPS로 리다이렉트하고, 내부 Puma 포트를 방화벽으로 외부 차단
- `/storage`나 프로젝트 루트 전체를 정적 파일 경로에 연결하지 않기
- 비공개 페이지·파일 응답을 프록시/CDN에 캐시하지 않기

APP_ENV=production에서는 로그인 쿠키에 Secure 플래그가 붙습니다. HTTPS 없이 접속하면 로그인 쿠키가 정상 동작하지 않습니다. HSTS 설정도 이 모드에서만 적용됩니다.

## 배포 환경에서 확인할 실제 동작

HTTPS에서 로그인하고 프로젝트 생성·수정·삭제, 파일 업로드·다운로드, 로그아웃을 확인하세요. 로그인하지 않은 별도 브라우저에서 비공개 프로젝트/첨부파일이 모두 404인지 확인하세요. 공개 파일의 다운로드 바이트와 원래 파일 이름도 확인해야 합니다.

문의 전송 후 관리자 문의함에 보이는지, 동의 없는 요청이 거부되는지, 비밀번호 변경 후 다른 기기의 로그인이 해제되는지 확인하세요. 프록시 뒤에서 모든 방문자의 문의가 하나의 IP 제한에 묶이는지도 점검하세요. 필요한 경우 프록시가 검증한 실제 클라이언트 주소를 별도 신뢰 경계 안에서 전달하도록 운영 설계를 조정해야 합니다.

프로세스 자동 재시작, 로그 보관, 저장소 권한, 디스크 경보, 백업/복원, 개인정보 보관 정책, 의존성 보안 업데이트도 배포자가 설정해야 합니다. 인증서 발급·도메인 연결·systemd 설치는 이 프로젝트가 자동 수행하지 않습니다.

## 의존성 기준

2026-09-08에 확인한 공개 배포용 Gemfile 하한: WEBrick 1.9.2, Rack 3.2.7, Puma 8.0.2. 이것이 앞으로의 최신 버전이나 모든 취약점이 없다는 보장은 아닙니다. 배포 전에 공식 릴리스와 보안 공지를 재확인하고 설치 후 생성되는 Gemfile.lock을 검토·보관하세요.

참고 문서:

https://github.com/ruby/webrick
https://puma.io/puma/file.README.html
https://puma.io/puma/Puma/DSL.html
https://rubygems.org/gems/rack
https://rubygems.org/gems/puma
