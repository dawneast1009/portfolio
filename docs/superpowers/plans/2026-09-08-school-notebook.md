# School Notebook Implementation Plan

**Goal:** Five-page editable Ruby portfolio with public-only static submission export.
**Architecture:** Extend the existing repository project records with notebook metadata. Reuse authentication, file permission checks and bounded HTTP parsing. Render both dynamic and static output through the same ERB templates.
**Tech Stack:** Ruby 3.3, ERB/HTML, CSS, browser JavaScript, PStore, WEBrick for local tests, Rack/Puma for deployment.
**Spec:** docs/superpowers/specs/2026-09-08-school-notebook.md

## Global Constraints
- Exactly five public navigation entries
- Preserve existing stored data and login credentials
- Admin-only mutations, CSRF, validated text and URLs
- Static exports contain public records/files only; no server credentials
- No new paid service; free Render cannot promise persistence

## Task 1: Notebook records and upload formats
Files: lib/portfolio/notebook.rb, repository.rb, uploads.rb, test/notebook_test.rb
Interfaces: Repository#save_entry(input, id: nil), #notebook_entries(page, section: nil, public_only: true); Notebook::PAGES
Write and run tests for required menus, page/section validation, levels, legacy fallback, invalid URLs, visibility and office attachments. Run `ruby test/notebook_test.rb`. Implement only after red, then rerun.

## Task 2: Five-page views and editor
Files: lib/portfolio/notebook_routes.rb, http_app.rb, view.rb, views/notebook/*, public/assets/notebook.css, app.js, test/notebook_http_test.rb
Interfaces: GET /career, /activities, /entry/:id; POST /admin/notebook; POST /admin/notebook/:id; POST /admin/notebook-upload
Reuse sessions and existing CSRF checks. Add failure-first request tests for anonymous access, editor save, upload/download, private entries and HTML escaping. Run `ruby test/notebook_http_test.rb` before and after implementation.

## Task 3: Share and public static export
Files: lib/portfolio/static_export.rb, bin/export, views/notebook/share.html.erb
Interface: StaticExport#entries -> Hash<String,String>; #archive -> binary ZIP
Tests inspect public-only export, relative navigation, removal of controls/credentials, duplicate filenames, max size and ZIP extraction. HTTP GET /admin/export.zip requires login.

## Task 4: Delivery and verification
Run `ruby bin/test`. Run real-browser tests at 360/390/768/1440px; inspect screenshots; test export under nested /repo/ path. Write Korean planning text and README with exact deployment limitations. Package clean source without storage, credentials, screenshots of sensitive pages or binary font files.
