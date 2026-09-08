# Portfolio Implementation Plan

**Goal:** Deliver a runnable Ruby + HTML portfolio with admin-only file uploads.
**Architecture:** HTTP boundary, domain/repository layer, security/upload policy, escaped ERB views. Local PStore persists content and files are stored separately.
**Tech Stack:** Ruby 3.3/3.4, WEBrick, PStore, ERB, OpenSSL, HTML/CSS/JavaScript, Minitest.
**Spec:** docs/superpowers/specs/2026-09-08-portfolio-design.md

## Global constraints
No fixed default password. No fabricated user credentials or achievements. No anonymous uploads. No external frontend dependencies. All draft file access is denied publicly. Default upload cap: 10 MiB. Private state never under public/.

## Task 1: Domain and security
- [x] Write `test/core_test.rb` covering password verification, sessions, persistence, project validation and upload/publication policy.
- [x] Run `ruby -Itest test/core_test.rb`; confirm missing implementation fails.
- [x] Implement `lib/portfolio/{security,store,repository,uploads}.rb` with the exact interfaces exercised by the tests.
- [x] Repeat `ruby -Itest test/core_test.rb` until all cases pass.

## Task 2: HTTP and HTML
- [x] Write `test/http_test.rb` to start a local ephemeral WEBrick server and exercise actual HTTP forms and cookies.
- [x] Implement `app.rb`, `lib/portfolio/{config,http_app,view}.rb`, `views/*.html.erb`, `views/admin/*.html.erb`, `public/assets/{site.css,app.js}`.
- [x] Run `ruby -Itest test/http_test.rb` for login, CSRF, draft isolation, contact persistence and file upload/download.
- [x] Verify actual HTTP response HTML at desktop/mobile widths using offline Chromium rendering; test menu/file-input JavaScript without browser network navigation. Full browser E2E is environment-limited.

## Task 3: Setup and delivery
- [x] Implement `bin/setup`, `bin/test`, README, `.env.example`, `.gitignore`, and Gemfile.
- [x] Fresh setup into a temporary storage directory; create a real admin and explicitly marked demo records.
- [x] Run all Ruby suites including real HTTP CRUD/upload and Rack adapter checks; save exact results in `docs/verification.md`.
- [x] Package source only, excluding passwords, session state, uploaded test files, runtime store, dependency caches and font files.

## Execution addition: deployment interface
- [x] Add `lib/portfolio/rack_app.rb`, `config.ru`, and `config/puma.rb`.
- [x] Reuse the real form/access tests through the Rack env/response interface.
- [x] Restrict WEBrick startup to local development and document untested Puma/TLS deployment.
