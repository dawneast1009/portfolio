# Supabase 무료 저장소 연결

무료 Render의 파일 시스템은 재시작·유휴 종료·재배포 때 초기화될 수 있습니다. 이 앱은 Supabase Postgres에 포트폴리오 상태를, Supabase Storage의 비공개 버킷에 업로드 파일을 보관해 Render가 다시 시작해도 복원할 수 있습니다.

## 1. Supabase 프로젝트 만들기

1. [Supabase](https://supabase.com/)에서 무료 프로젝트를 만듭니다.
2. `Storage → New bucket`을 선택합니다.
3. 버킷 이름을 `portfolio-data`로 만들고 **Public bucket을 끕니다**.
4. `Project Settings → API`에서 `Project URL`과 `service_role` 키를 확인합니다. service_role 키는 서버 비밀값이므로 GitHub나 브라우저에 올리지 않습니다.

## 2. 상태 테이블 만들기

Supabase SQL Editor에서 [`supabase/schema.sql`](supabase/schema.sql)의 내용을 실행합니다. 이미 테이블을 만들었다면 파일의 마지막 `grant` 문장도 다시 실행하세요. `portfolio_state`는 서버만 사용하는 단일 상태 행이며, RLS가 켜져 있어 공개 API에서 읽을 수 없습니다.

무료 플랜은 프로젝트당 Storage 1GB를 제공하고, 무료 프로젝트의 파일 하나는 최대 50MB입니다. 이 앱의 기본 파일 제한은 파일당 10MB입니다. 무료 프로젝트는 장기간 사용하지 않으면 일시 중지될 수 있지만 저장된 데이터는 유지됩니다.

## 3. Render 환경변수 설정

Render 서비스의 `Environment`에 다음 값을 추가합니다.

| 이름 | 값 |
| --- | --- |
| `SUPABASE_URL` | Supabase Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase `service_role` 키 (Secret) |
| `SUPABASE_BUCKET` | `portfolio-data` |

`SUPABASE_SERVICE_ROLE_KEY`는 반드시 Secret으로 저장하세요. 공개 페이지를 보는 데는 로그인이 필요 없고, 소개·목차·글·파일을 수정할 때만 기존 관리자 로그인이 필요합니다.

환경변수를 저장하고 Render에서 한 번 재배포하면 앱이 테이블의 상태 행과 버킷의 `files/` 객체를 사용합니다. 원격 저장소에 아직 상태가 없으면 첫 번째 관리자 저장 때 자동으로 생성됩니다.

## 4. 기존 로컬 자료 올리기

Render에 올리기 전에 로컬 `.env`에 세 값을 넣고, 기존 `storage/`가 있는 프로젝트 폴더에서 실행합니다.

```bash
ruby bin/supabase-migrate
```

이 명령은 기존 `storage/portfolio.pstore`와 업로드 파일을 원격에 한 번 올립니다. 이미 원격 상태가 있으면 덮어쓰지 않고 중단합니다. 계정 비밀번호와 비공개 자료도 원격에 저장되므로 버킷을 공개로 바꾸지 마세요.

## 5. 확인

Render 재배포 뒤 관리자에서 로그인해 기존 목차와 글을 확인합니다. 공개 홈은 로그인 없이 열리고, `/admin/navigation` 같은 편집 주소는 로그인 화면으로 이동해야 정상입니다. Supabase 키나 `storage/` 폴더는 GitHub에 커밋하지 않습니다.
