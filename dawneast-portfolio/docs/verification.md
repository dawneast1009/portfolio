# 검증 기록

검증일: 2026-09-08

## 실제 실행 환경

- Debian GNU/Linux 13, x86_64
- Ruby 3.3.8
- WEBrick 1.9.1
- Minitest 5.20.0
- Chromium 144.0.7559.96

실행 환경에는 WEBrick 1.9.1이 설치되어 있었으며 외부 gem 설치 네트워크를 사용할 수 없었습니다. 따라서 WEBrick 1.9.2 / Rack 3.2.7 / Puma 8.0.2를 실제 설치한 결과로 아래 테스트를 해석하면 안 됩니다. Gemfile은 사용자 설치·공개 배포용 버전 하한을 별도로 명시합니다. Ruby 3.4와 Windows 네이티브 환경도 이 작업에서 실행하지 않았습니다.

## Ruby 테스트 결과

프로젝트 루트에서 실행한 명령:

```bash
ruby bin/test
```

실제 출력:

```text
Run options: --seed 37901

73 runs, 495 assertions, 0 failures, 0 errors, 0 skips
```

원본 출력: `docs/test-results.txt`

| 테스트 구성 | 건수 | 실행 방식 |
| --- | ---: | --- |
| core_test.rb | 22 | 임시 PStore·파일 저장소를 사용하는 도메인/보안 테스트 |
| http_test.rb | 22 | 로컬 WEBrick 서버를 실제 띄우고 Net::HTTP로 요청 |
| rack_test.rb | 24 | 동일 요청 검증을 Rack env/response 인터페이스에 적용 + HEAD/Secure 쿠키 검사 |
| setup_test.rb | 5 | setup 프로그램을 자식 프로세스로 실행해 계정 생성·재설정 검사 |
| 합계 | 73 | 실패·오류·건너뜀 없음 |

주요 확인 사항: 계정 해시·인증, 세션 교체·로그아웃·비밀번호 변경 후 기존 로그인 해제, CSRF·Origin·Host 검사, 요청 크기 제한, 프로젝트 생성/수정/삭제/검색, 비공개 프로젝트와 첨부파일 차단, 실제 multipart 업로드와 다운로드 바이트, 한글 파일명, 파일 내용 검증 및 중복 필드 거부, 저장 용량·고아 파일 처리, 이미지 대표 설정·공개 전환·삭제, 프로필·이력서 링크, 문의 수집 동의·허니팟·읽음·삭제·출력 이스케이프, 샘플 일괄 삭제.

Rack 테스트는 HTTP 테스트를 상속해 같은 검증을 별도 어댑터에 실행합니다. 테스트 건수에는 이 재실행이 포함됩니다. **실제 Puma 프로세스를 시작한 테스트는 아닙니다.**

## 구문 검사

`ruby -c`로 app.rb, config.ru, config/puma.rb, bin/setup, bin/test, lib/portfolio/*.rb, test/*_test.rb를 확인했습니다. 모두 성공했습니다.

`node --check public/assets/app.js`도 성공했습니다. 애플리케이션 실행에 Node는 필요하지 않으며 이 명령은 JavaScript 구문 검사에만 사용했습니다.

## 화면과 JavaScript 확인

이 환경의 Chromium은 URL 네트워크 탐색이 차단되어 있습니다. 따라서 브라우저에서 로컬 주소로 이동하며 폼을 제출하는 완전한 E2E 테스트는 수행하지 못했습니다.

대신 실제 로컬 서버에 HTTP로 로그인하고 각 화면의 **실제 응답 HTML**을 가져와, 해당 프로젝트의 CSS와 JavaScript를 적용한 상태로 Chromium에 오프라인 렌더링했습니다. 사이트를 대신한 별도 목업을 만든 것이 아닙니다. 렌더링 캡처에는 공개 샘플 데이터가 사용됐습니다.

11개 화면 × 4개 너비 = 44개 레이아웃을 확인했습니다.

화면: `/`, `/projects`, `/files`, `/about`, `/contact`, `/admin`, `/admin/files`, `/admin/projects/new`, `/admin/profile`, `/admin/inbox`, `/admin/security`

너비: 360, 390, 768, 1440px

44개 모두 document의 가로 길이가 화면 너비를 넘지 않았습니다. 관리자 표 내부의 의도된 가로 스크롤은 허용했습니다. 검사 과정에서 JavaScript pageerror는 0건이었습니다.

390px에서 모바일 메뉴 열기와 Escape로 닫기를 확인했습니다. 파일 관리 화면에서 파일 선택 후 파일명 표시와 허용하지 않는 확장자의 입력 오류 처리를 4개 너비에서 확인했습니다. 실제 HTTP 파일 업로드/다운로드 동작은 위 Ruby HTTP 테스트에서 별도로 확인했습니다.

원본 결과: `docs/visual-report.json`

## 산출물과 제외 항목

소스 프로젝트에는 실행 프로그램, HTML/CSS/JS, 설정 예시, 테스트, 문서를 포함합니다. 실제 관리자 데이터, .env, 세션, 테스트 업로드 저장소, 비밀번호 파일, 폰트 파일, gem 캐시는 포함하지 않습니다. storage/에는 .gitkeep만 포함합니다.

스크린샷은 별도 미리보기 파일로 제공합니다. 샘플은 실제 사용자 경력으로 제시하지 않습니다.

## 하지 않은 검증

공개 배포·도메인·TLS 연동, Puma 프로세스 실행, 실제 운영 데이터 이관, SMTP 발송, 악성 파일 엔진 검사, 대규모 부하 테스트, 독립적인 외부 보안 감사는 수행하지 않았습니다. 브라우저 네트워크 기반 E2E 및 브라우저별 전체 호환성 검증도 수행하지 않았습니다.

테스트 통과는 코드의 모든 결함이 없거나 운영 안전성이 보장된다는 의미가 아닙니다. 공개 배포 전에 `docs/deployment.md`의 배포 환경 검증을 진행하세요.
