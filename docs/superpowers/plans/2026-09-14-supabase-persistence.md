# Supabase Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Persist portfolio state in Supabase Postgres and uploaded files through a private Supabase Storage bucket while keeping public viewing open and edits login-protected.

**Architecture:** Add Supabase Postgres as a revision-checked state authority and a private Storage object client for file bytes behind the existing `Store` interface. Conditional revision updates prevent stale Render containers from overwriting edits; local PStore remains the fallback when Supabase variables are absent, while configured production startup fails closed if the remote is unavailable.

**Tech Stack:** Ruby standard library (`Net::HTTP`, `JSON`), PStore, Supabase PostgREST and Storage REST APIs, existing WEBrick/Puma/Rack adapters, Minitest.

**Spec:** `docs/superpowers/specs/2026-09-14-supabase-persistence-design.md`

## Global Constraints

- Public pages remain readable without a session.
- Existing username/password login and CSRF protection remain required for every `/admin` mutation.
- Never expose `SUPABASE_SERVICE_ROLE_KEY` to templates, exports, logs, or browser JavaScript.
- Preserve local PStore behavior when Supabase variables are absent.
- Preserve the existing 10 MiB per-file and 100 MiB Render preview limits.

---

### Task 1: Add remote object persistence primitives

**Files:**
- Create: `lib/portfolio/supabase_persistence.rb`
- Modify: `lib/portfolio/store.rb`
- Test: `test/supabase_persistence_test.rb`

**Interfaces:**
- `SupabasePersistence.from_env(env)` returns `nil` when `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are both absent, otherwise returns a configured adapter.
- `restore_state` returns a decoded state hash plus revision or `nil` for a missing `portfolio_state` row.
- `save_state(state, expected_revision:)` performs a conditional Postgres update/insert and returns the new revision; `upload_file(id, bytes)`, `download_file(id)`, and `delete_file(id)` synchronize private objects.
- `Store.new(directory, persistence: nil)` restores remote state before creating the local PStore and invokes `persistence.save_state(state, expected_revision:)` after successful updates.

- [ ] **Step 1: Write failing persistence tests**

Create an in-memory fake object client and test that a repository created with one adapter instance writes state and a file, then a second repository restores both. Test missing remote state, remote download failure during startup, and local behavior with `persistence: nil`.

- [ ] **Step 2: Run the focused tests**

Run: `ruby -Itest test/supabase_persistence_test.rb`
Expected: failures because the adapter and Store persistence hook do not exist.

- [ ] **Step 3: Implement the adapter and Store hook**

Use `Net::HTTP` with HTTPS-only Supabase URLs, `Authorization: Bearer <service-role-key>`, `apikey`, revision-filtered PostgREST requests for `portfolio_state`, and binary Storage objects. Treat HTTP 404 for downloads as a missing object, reject non-2xx responses with a configuration error, reject zero-row revision updates as a persistence conflict, and never include the key in exception text. Make `Store` restore the remote state before initializing defaults and synchronize inside each local transaction before committing it.

- [ ] **Step 4: Run the focused tests**

Run: `ruby -Itest test/supabase_persistence_test.rb`
Expected: all persistence tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/portfolio/supabase_persistence.rb lib/portfolio/store.rb test/supabase_persistence_test.rb
git commit -m "Add Supabase object persistence"
```

### Task 2: Synchronize uploaded files and wire application construction

**Files:**
- Modify: `lib/portfolio/repository.rb`
- Modify: `app.rb`
- Modify: `config.ru`
- Modify: `lib/portfolio/rack_app.rb`
- Modify: `lib/portfolio/deployment.rb`
- Modify: `bin/setup`
- Modify: `bin/export`
- Test: `test/supabase_persistence_test.rb`, `test/deployment_test.rb`

**Interfaces:**
- `Repository.new(directory, ..., persistence: nil)` passes the adapter to `Store` and exposes no credentials.
- File creation uploads `files/<id>.blob` before the metadata transaction is published; deletion removes the remote object after metadata removal.
- All app entry points construct the same optional persistence adapter from `Config`/environment.

- [ ] **Step 1: Add failing file-sync and wiring tests**

Extend `test/supabase_persistence_test.rb` to assert uploaded bytes, deletion, and restoration through `Repository`. Add deployment tests for missing Supabase variables in local mode and for a configured adapter being passed without logging its key.

- [ ] **Step 2: Run focused tests to verify failure**

Run: `ruby -Itest test/repository_test.rb test/deployment_test.rb`
Expected: failures for missing constructor wiring and file synchronization.

- [ ] **Step 3: Implement minimal wiring**

Add a shared `Persistence.from_env` factory, pass it from every runtime entry point, and update `Repository#add_file`, `delete_file`, `delete_project`, and `clear_demo` so remote objects follow local metadata. Keep cleanup best-effort after a committed deletion; never silently use local-only storage when remote persistence is explicitly configured.

- [ ] **Step 4: Run focused tests**

Run: `ruby -Itest test/repository_test.rb test/deployment_test.rb`
Expected: focused tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/portfolio/repository.rb app.rb config.ru lib/portfolio/rack_app.rb lib/portfolio/deployment.rb bin/setup bin/export test/supabase_persistence_test.rb test/deployment_test.rb
git commit -m "Wire Supabase persistence into runtime"
```

### Task 3: Add Render configuration and setup/migration documentation

**Files:**
- Create: `SUPABASE_SETUP.md`
- Modify: `README.md`
- Modify: `docs/deployment.md`
- Modify: `render-free.yaml`
- Test: `test/deployment_test.rb`

**Interfaces:**
- Render variables are `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (secret), and `SUPABASE_BUCKET` (optional).
- Setup instructions create a private `portfolio-data` bucket and configure the variables without committing secrets.
- A migration command uploads an existing local `storage/` state and file objects before the first Render restart.

- [ ] **Step 1: Write configuration/documentation tests**

Assert the free Blueprint documents the optional Supabase variables without putting a secret value in YAML, and assert the setup guide names the private bucket, service-role key placement, migration command, and 1 GB/50 MB operational limits.

- [ ] **Step 2: Implement setup and migration guidance**

Document the Supabase Dashboard steps, setup SQL, Render Environment settings, private bucket requirement, and `ruby bin/supabase-migrate` command. Explain that public viewing is open while editing still requires login, and that Supabase Free may pause after inactivity while retaining data.

- [ ] **Step 3: Run documentation/configuration tests**

Run: `ruby -Itest test/deployment_test.rb`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add SUPABASE_SETUP.md README.md docs/deployment.md render-free.yaml test/deployment_test.rb
git commit -m "Document Supabase durable storage setup"
```

### Task 4: Verify end-to-end behavior and integrate

**Files:**
- Test: all existing `test/**/*_test.rb`

- [ ] **Step 1: Run the complete suite**

Run: `ruby bin/test`
Expected: zero failures and zero errors.

- [ ] **Step 2: Run syntax and diff checks**

Run: `git diff --check`; compile all ERB templates with Ruby's `ERB` compiler; run `ruby -c` on changed Ruby files.
Expected: all checks pass.

- [ ] **Step 3: Verify no secret leakage**

Run: `rg -n "SUPABASE_SERVICE_ROLE_KEY|service-role|SUPABASE_URL" README.md SUPABASE_SETUP.md docs render-free.yaml lib test` and inspect that only variable names and setup placeholders occur, never a key value.

- [ ] **Step 4: Commit final verification updates**

```bash
git add docs/verification.md
git commit -m "Verify Supabase persistence integration"
```
