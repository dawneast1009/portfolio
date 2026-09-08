# Portfolio design

## Scope and decisions
A runnable, single-owner portfolio. Backend: Ruby. Frontend: server-rendered HTML / ERB, CSS, progressive-enhancement JavaScript. No Node build step, SPA, hosted database, or third-party UI service. WEBrick handles local-development HTTP; a Rack adapter plus Puma configuration is included for deployment; Ruby PStore stores local application data. The default network bind is loopback.

White editorial layout, dark navy text, restrained blue accents, thin borders, compact conventional navigation. Responsive public pages and an equally practical admin console. Default nickname: dawneast. Demo projects are explicitly marked, not presented as verified accomplishments.

## Features
Public home, searchable/tag-filtered project index, project detail, about section, public download library, contact form. Admin login/logout, project create/update/delete, draft/published states, featured projects, file upload/download/delete, image covers, profile/social-link editing, inbox read/delete, password change, and demo-content removal. No visitor registration and no anonymous uploads.

## Data and access
Projects and files have random identifiers. Public files must be marked public and must not belong to a draft project. Private files, image previews, and resume links obey the same policy. Uploaded bytes live outside public/. Passwords use OpenSSL PBKDF2-HMAC-SHA256 with a per-password salt and 600,000 iterations. Sessions are opaque, server-side, bounded and expiring; login rotates the session and logout revokes it. Password changes invalidate old authenticated sessions.

Uploads: one file per request; default 10 MiB/file, 12 MiB/request, 500 MiB total. Allow PDF, PNG, JPG/JPEG, WEBP, TXT, MD, ZIP. Validate actual byte length, extension and basic format signatures; never extract archives or execute content. Original names are display metadata only. General downloads force attachment and nosniff. Signature checks are not malware scanning.

All mutations are POST with CSRF validation; templates escape stored input; external links permit HTTP(S) only; CSP, no-store for private pages, Host checks and bounded request bodies are required. Contact and login have local rate limits. All private state is local; contact does not send email. Storage is for a small single-process site, not multi-node deployment.

## Delivery and evidence
Source zip, Korean README, setup utility without a fixed default password, direct Ruby start command, unit and live HTTP integration tests, desktop/mobile offline rendering of actual server responses plus JavaScript interaction checks and screenshots. Browser network navigation is blocked in this environment; full browser-through-network E2E is not claimed. Recommended dependency: WEBrick 1.9.2 or later compatible release. Document any difference between installed test dependencies and deployment requirements. No claim of public deployment or a successful Puma process launch in this environment.
