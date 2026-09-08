# Editable Portfolio Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an authenticated administrator add, edit, reorder, and safely delete portfolio pages and their sections from the site UI.

**Architecture:** Store a navigation tree in the existing PStore state and fall back to a deep copy of the current five-page tree for old stores. Stable generated IDs remain the routing and record-assignment keys while editable titles control display. Repository methods own transactional validation and deletion guards; HTTP routes, views, record editing, and static export all consume the same repository-provided tree.

**Tech Stack:** Ruby 3.x, PStore, WEBrick/Rack adapters, ERB, Minitest, existing CSS and vanilla JavaScript

**Spec:** `docs/superpowers/specs/2026-09-09-editable-navigation-design.md`

## Global Constraints

- Preserve the existing IDs `home`, `about`, `career`, `activities`, `projects` and all current section IDs.
- Keep `/` as the home route and preserve `/about`, `/career`, `/activities`, and `/projects`.
- Generate new page IDs as `page-` plus 12 lowercase hexadecimal characters and new section IDs as `section-` plus 12 lowercase hexadecimal characters.
- Allow at most 20 pages including home and at most 30 sections per page.
- Accept page titles of 1–60 characters, descriptions of 0–300 characters, and section titles of 1–60 characters.
- Allow only the existing `file`, `user`, `pin`, `grid`, and `folder` navigation icons.
- Never delete a page or section with linked records; never delete or move the home page.
- Require an authenticated session and a valid CSRF token for every navigation mutation.
- Keep the static export public-only and within its existing 64 MiB limit.
- Keep the existing warning that free Render storage can disappear on restart or redeploy.

---

### Task 1: Persist and validate the navigation tree

**Files:**
- Modify: `lib/portfolio/notebook.rb`
- Modify: `lib/portfolio/repository.rb`
- Test: `test/notebook_test.rb`

**Interfaces:**
- Produces: `Portfolio::Notebook.default_navigation -> Array<Hash>`
- Produces: `Portfolio::Notebook.page(navigation, id) -> Hash | nil`
- Produces: `Portfolio::Notebook.section(page, id) -> Hash | nil`
- Produces: `Portfolio::Repository#notebook_navigation -> Array<Hash>`
- Produces: `save_notebook_page(input, id: nil)`, `move_notebook_page(id, direction)`, `delete_notebook_page(id)`
- Produces: `save_notebook_section(page_id, input, id: nil)`, `move_notebook_section(page_id, id, direction)`, `delete_notebook_section(page_id, id)`
- Preserves: `save_entry`, `notebook_entries`, and legacy-project fallback behavior

- [ ] **Step 1: Add failing repository tests for default compatibility and persistence**

Add tests that prove a new store exposes the current IDs without writing custom navigation and that additions and renames survive a new repository instance:

```ruby
def test_navigation_defaults_preserve_existing_ids_and_urls
  navigation = @repo.notebook_navigation
  assert_equal %w[home about career activities projects], navigation.map { |page| page['id'] }
  assert_equal %w[strengths interests values career_history], navigation[1]['sections'].map { |section| section['id'] }
  assert_equal '/', Portfolio::Notebook.path('home')
  assert_equal '/about', Portfolio::Notebook.path('about')
end

def test_navigation_page_and_section_changes_persist_with_stable_ids
  page = @repo.save_notebook_page('title'=>'수상 기록', 'description'=>'받은 상을 정리합니다', 'icon'=>'folder')
  section = @repo.save_notebook_section(page['id'], {'title'=>'교내 수상'})
  @repo.save_notebook_page({'title'=>'수상 및 자격', 'description'=>'수상과 자격증', 'icon'=>'file'}, id:page['id'])
  @repo.save_notebook_section(page['id'], {'title'=>'학교 수상'}, id:section['id'])
  reloaded = Portfolio::Repository.new(@dir)
  saved_page = Portfolio::Notebook.page(reloaded.notebook_navigation, page['id'])
  assert_equal '수상 및 자격', saved_page['title']
  assert_equal section['id'], saved_page['sections'].first['id']
  assert_equal '학교 수상', saved_page['sections'].first['title']
end
```

- [ ] **Step 2: Run the new tests and verify RED**

Run: `ruby -Itest test/notebook_test.rb --name '/test_navigation_/'`

Expected: failures report that `Portfolio::Repository` does not respond to `notebook_navigation` and `save_notebook_page`.

- [ ] **Step 3: Implement immutable defaults, lookup helpers, and repository persistence**

In `Portfolio::Notebook`, represent defaults as arrays of string-keyed hashes, deep-freeze the constant, and return a Marshal deep copy:

```ruby
ICONS = %w[file user pin grid folder].freeze
MAX_PAGES = 20
MAX_SECTIONS = 30

def default_navigation
  Marshal.load(Marshal.dump(DEFAULT_NAVIGATION))
end

def page(navigation, id)
  navigation.find { |item| item['id'] == id.to_s }
end

def section(page_record, id)
  page_record && page_record['sections'].find { |item| item['id'] == id.to_s }
end

def path(page_id)
  page_id == 'home' ? '/' : "/#{page_id}"
end
```

In `Portfolio::Repository`, read the saved tree or return a fresh default. For every mutation, initialize `state['notebook_navigation'] ||= Notebook.default_navigation` inside `@store.update`, locate the requested parent by stable ID, validate through the existing private `text` helper, and return a deep copy of the affected item. Generate IDs with `SecureRandom.hex(6)`:

```ruby
def notebook_navigation
  navigation = @store.read['notebook_navigation'] || Notebook.default_navigation
  Marshal.load(Marshal.dump(navigation))
end

def save_notebook_page(input, id: nil)
  title = text(input, 'title', max:60, required:true)
  description = text(input, 'description', max:300)
  icon = input['icon'].to_s
  raise ValidationError, '목차 아이콘을 다시 선택해 주세요' unless Notebook::ICONS.include?(icon)
  @store.update do |state|
    navigation = state['notebook_navigation'] ||= Notebook.default_navigation
    raise ValidationError, '상위 메뉴는 최대 20개까지 만들 수 있습니다' if !id && navigation.size >= Notebook::MAX_PAGES
    item = id ? Notebook.page(navigation, id) : nil
    raise NotFound if id && !item
    item ||= { 'id'=>"page-#{SecureRandom.hex(6)}", 'sections'=>[] }
    navigation << item unless id
    item.merge!('title'=>title, 'description'=>description, 'icon'=>icon)
    Marshal.load(Marshal.dump(item))
  end
end
```

Implement the section save method with the same pattern, a 60-character required title, the 30-section cap, and `section-#{SecureRandom.hex(6)}` IDs.

- [ ] **Step 4: Add failing tests for ordering, deletion guards, limits, and record assignment**

Add separate tests that move a new page above `projects`, move a new section up, reject moving `home`, reject deletion when a record is linked, allow deletion when empty, reject invalid icons and blank titles, and prove a renamed section still owns its record:

```ruby
def test_navigation_reorders_and_deletes_only_empty_items
  page = @repo.save_notebook_page('title'=>'수상', 'description'=>'', 'icon'=>'folder')
  first = @repo.save_notebook_section(page['id'], {'title'=>'교내'})
  second = @repo.save_notebook_section(page['id'], {'title'=>'교외'})
  @repo.move_notebook_section(page['id'], second['id'], 'up')
  assert_equal [second['id'], first['id']], Portfolio::Notebook.page(@repo.notebook_navigation, page['id'])['sections'].map { |item| item['id'] }
  @repo.move_notebook_page(page['id'], 'up')
  assert_equal page['id'], @repo.notebook_navigation[-2]['id']
  @repo.delete_notebook_section(page['id'], first['id'])
  refute Portfolio::Notebook.section(Portfolio::Notebook.page(@repo.notebook_navigation, page['id']), first['id'])
end

def test_navigation_refuses_to_delete_items_with_records_or_home
  item = entry
  error = assert_raises(Portfolio::ValidationError) { @repo.delete_notebook_section('about', 'strengths') }
  assert_includes error.message, '기록'
  assert_raises(Portfolio::ValidationError) { @repo.delete_notebook_page('about') }
  assert_raises(Portfolio::ValidationError) { @repo.delete_notebook_page('home') }
  assert_equal item['id'], @repo.notebook_entries('about', section:'strengths').first['id']
end

def test_navigation_validates_names_icons_and_limits
  assert_raises(Portfolio::ValidationError) { @repo.save_notebook_page('title'=>'', 'description'=>'', 'icon'=>'folder') }
  assert_raises(Portfolio::ValidationError) { @repo.save_notebook_page('title'=>'기타', 'description'=>'', 'icon'=>'script') }
  15.times { |index| @repo.save_notebook_page('title'=>"추가 #{index}", 'description'=>'', 'icon'=>'file') }
  assert_raises(Portfolio::ValidationError) { @repo.save_notebook_page('title'=>'초과', 'description'=>'', 'icon'=>'file') }
end
```

- [ ] **Step 5: Run focused tests and verify RED**

Run: `ruby -Itest test/notebook_test.rb --name '/test_navigation_/'`

Expected: the new ordering and deletion tests fail because their repository methods do not exist.

- [ ] **Step 6: Implement transactional move and delete operations and dynamic record validation**

Use only `up` and `down` directions. Boundary moves return without changing the array. For page deletion, evaluate linked records with `Notebook.page_of(record, navigation) == id`; for section deletion, require both `Notebook.page_of(record, navigation) == page_id` and `Notebook.section_of(record, navigation) == id`. Raise a Korean `ValidationError` when records exist or when `home` is targeted.

Change the record helpers to accept navigation explicitly:

```ruby
def page_of(record, navigation = DEFAULT_NAVIGATION)
  id = record['notebook_page']
  page(navigation, id) ? id : 'projects'
end

def section_of(record, navigation = DEFAULT_NAVIGATION)
  page_id = page_of(record, navigation)
  page_record = page(navigation, page_id)
  id = record['notebook_section']
  return id if section(page_record, id)
  page_id == 'projects' && section(page_record, 'personal') ? 'personal' : page_record['sections'].first&.fetch('id')
end
```

Make `save_entry` and `notebook_entries` validate and resolve records using `notebook_navigation`. Reject creating a record when the selected page has no section.

Update the existing `test_five_exact_menus_and_school_categories` test to assert against `@repo.notebook_navigation` and its string-keyed page and section records instead of the removed runtime `Notebook::PAGES` lookup.

- [ ] **Step 7: Run the model tests and commit**

Run: `ruby -Itest test/notebook_test.rb`

Expected: all `NotebookTest` tests pass with zero failures and zero errors.

Commit:

```bash
git add lib/portfolio/notebook.rb lib/portfolio/repository.rb test/notebook_test.rb
git commit -m "Add persistent editable navigation model"
```

---

### Task 2: Add the authenticated navigation management screen

**Files:**
- Modify: `lib/portfolio/notebook_routes.rb`
- Create: `views/admin/navigation.html.erb`
- Modify: `views/notebook/layout.html.erb`
- Modify: `views/notebook/page.html.erb`
- Modify: `public/assets/notebook.css`
- Test: `test/notebook_http_test.rb`

**Interfaces:**
- Consumes: all repository navigation mutation methods from Task 1
- Produces: `GET /admin/navigation`
- Produces: POST routes under `/admin/navigation/pages`
- Produces: authenticated `목차 편집` links on home and in the sidebar

- [ ] **Step 1: Add failing HTTP tests for authentication, rendering, mutation, and CSRF**

Add tests that verify anonymous access redirects, the logged-in screen contains all default pages, a valid request adds a page, and a missing token returns 403:

```ruby
def test_navigation_manager_requires_login_and_csrf
  assert_equal '303', request('GET','/admin/navigation').code
  token = login
  page = request('GET','/admin/navigation')
  assert_equal '200', page.code
  assert_includes page.body.force_encoding('UTF-8'), '내 소개'
  denied = request('POST','/admin/navigation/pages', form:{'title'=>'수상','description'=>'','icon'=>'folder'})
  assert_equal '403', denied.code
  created = request('POST','/admin/navigation/pages', form:{'_csrf'=>token,'title'=>'수상','description'=>'받은 상','icon'=>'folder'})
  assert_equal '303', created.code
  assert @repo.notebook_navigation.any? { |item| item['title'] == '수상' }
end
```

Add one request-level test covering page update, section create/update, both move directions, empty deletion, home deletion rejection, and the `422` response when deleting an item that owns a record.

- [ ] **Step 2: Run the focused HTTP tests and verify RED**

Run: `ruby -Itest test/notebook_http_test.rb --name '/navigation/'`

Expected: `GET /admin/navigation` returns 404 after login and the create request does not add a page.

- [ ] **Step 3: Add management routes and error rendering**

Extend `NotebookRoutes#dispatch_get` with `/admin/navigation`. Extend `dispatch_post` with these exact route shapes, using a safe navigation ID pattern of `[a-z0-9-]{1,40}` and repository lookup for final authorization:

```text
POST /admin/navigation/pages
POST /admin/navigation/pages/:page_id
POST /admin/navigation/pages/:page_id/move
POST /admin/navigation/pages/:page_id/delete
POST /admin/navigation/pages/:page_id/sections
POST /admin/navigation/pages/:page_id/sections/:section_id
POST /admin/navigation/pages/:page_id/sections/:section_id/move
POST /admin/navigation/pages/:page_id/sections/:section_id/delete
```

Pass `@params['direction']` only to move methods. Redirect successful mutations to `/admin/navigation` with a concrete flash message. Rescue `ValidationError` in a shared navigation action wrapper and render the management view with status 422 and the exception message.

- [ ] **Step 4: Build the server-rendered management UI**

Create `views/admin/navigation.html.erb` with:

- one page card per saved page;
- a page edit form containing title, description, and an icon select sourced from `Notebook::ICONS`;
- separate POST forms for up, down, and delete;
- a section edit row with a title field plus up, down, and delete forms;
- a section create form under every page;
- a page create form after the existing page cards;
- `data-confirm="이 메뉴를 삭제할까요?"` on destructive forms;
- disabled movement controls at boundaries and no delete/move controls for `home`.

Every POST form must include `<%= csrf_field %>`. Escape every title, description, ID, and message with `h` or `field`.

- [ ] **Step 5: Add navigation-management links and responsive styles**

Add `/admin/navigation` as `목차 편집` in the authenticated sidebar. On the home heading, replace the single action with an action group containing `소개 수정` and `목차 편집`. Add focused CSS for `.heading-actions`, `.navigation-card`, `.navigation-page-form`, `.navigation-section-row`, `.navigation-controls`, and mobile stacking under the existing `max-width:767px` media query.

- [ ] **Step 6: Run HTTP tests and commit**

Run: `ruby -Itest test/notebook_http_test.rb`

Expected: all notebook HTTP tests pass with zero failures and zero errors.

Commit:

```bash
git add lib/portfolio/notebook_routes.rb views/admin/navigation.html.erb views/notebook/layout.html.erb views/notebook/page.html.erb public/assets/notebook.css test/notebook_http_test.rb
git commit -m "Add navigation management screen"
```

---

### Task 3: Drive public pages and record editing from saved navigation

**Files:**
- Modify: `lib/portfolio/notebook_routes.rb`
- Modify: `lib/portfolio/view.rb`
- Modify: `views/notebook/layout.html.erb`
- Modify: `views/notebook/page.html.erb`
- Modify: `views/notebook/editor.html.erb`
- Modify: `views/notebook/entry.html.erb`
- Test: `test/notebook_http_test.rb`
- Test: `test/http_test.rb`

**Interfaces:**
- Consumes: `Repository#notebook_navigation` and stable page/section IDs
- Produces: dynamic public paths for every saved page
- Produces: view helpers `notebook_pages`, `notebook_page(id)`, and `notebook_section(page_id, section_id)`

- [ ] **Step 1: Add failing end-to-end rendering tests**

Add a page and section through the repository, save a published record, and assert the new public route, sidebar, home index, editor, and renamed labels all use the stored tree:

```ruby
def test_custom_navigation_drives_public_pages_and_record_editor
  login
  page = @repo.save_notebook_page('title'=>'수상','description'=>'도전의 결과','icon'=>'folder')
  section = @repo.save_notebook_section(page['id'], {'title'=>'교내 수상'})
  item = @repo.save_entry('title'=>'과학상','body'=>'탐구 결과','page'=>page['id'],'section'=>section['id'],'status'=>'published','level'=>'')
  public_page = request('GET', "/#{page['id']}", cookie:false)
  assert_equal '200', public_page.code
  assert_includes public_page.body.force_encoding('UTF-8'), '수상'
  assert_includes public_page.body.force_encoding('UTF-8'), '과학상'
  assert_includes request('GET','/',cookie:false).body.force_encoding('UTF-8'), '교내 수상'
  editor = request('GET', "/admin/notebook/#{item['id']}/edit")
  assert_equal '200', editor.code
  assert_includes editor.body.force_encoding('UTF-8'), '교내 수상'
  assert_includes request('GET','/admin/navigation').body.force_encoding('UTF-8'), '목차 관리'
end
```

Also assert that an unknown `/page-000000000000` path returns 404 and an anonymous page never includes `/admin/navigation`.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `ruby -Itest test/notebook_http_test.rb --name test_custom_navigation_drives_public_pages_and_record_editor`

Expected: the custom public page returns 404 because request dispatch still reads the fixed `Notebook::PAGES` constant.

- [ ] **Step 3: Replace runtime constant lookups with repository navigation**

In `View#initialize`, set `@navigation = repository.notebook_navigation`. Add these helpers:

```ruby
def notebook_pages = @navigation
def notebook_page(id) = Notebook.page(@navigation, id)
def notebook_section(page_id, section_id) = Notebook.section(notebook_page(page_id), section_id)
```

Resolve `current_page`, `current_title`, record page, record section, and page links through those helpers. In `NotebookRoutes`, match public pages by comparing `@path` with `Notebook.path(page['id'])`, validate new-entry page and section IDs against `@repo.notebook_navigation`, and pass the stored page hash to rendering.

Update the layout, home index, section loops, entry back link, and editor select to iterate `notebook_pages` and string-keyed stored fields. Keep the home headline and intro sourced from the profile while its menu title and sidebar label come from navigation.

- [ ] **Step 4: Run the HTTP and Rack suites and commit**

Run: `ruby -Itest test/notebook_http_test.rb && ruby -Itest test/rack_test.rb`

Expected: all tests in both files pass with zero failures and zero errors.

Commit:

```bash
git add lib/portfolio/notebook_routes.rb lib/portfolio/view.rb views/notebook/layout.html.erb views/notebook/page.html.erb views/notebook/editor.html.erb views/notebook/entry.html.erb test/notebook_http_test.rb test/http_test.rb
git commit -m "Render portfolio from saved navigation"
```

---

### Task 4: Include custom navigation in static exports and documentation

**Files:**
- Modify: `lib/portfolio/static_export.rb`
- Modify: `test/notebook_test.rb`
- Modify: `README.md`
- Modify: `docs/verification.md`

**Interfaces:**
- Consumes: `Repository#notebook_navigation`
- Produces: `Repository#public_notebook_snapshot` with a `navigation` member
- Produces: static HTML files for every saved page ID

- [ ] **Step 1: Add a failing static-export test for a custom page**

Extend the export test with a custom page and assert that its file, title, section, record, home link, and relative sidebar link are present:

```ruby
page = @repo.save_notebook_page('title'=>'수상','description'=>'도전의 결과','icon'=>'folder')
section = @repo.save_notebook_section(page['id'], {'title'=>'교내 수상'})
custom = entry('title'=>'공개 수상 기록','page'=>page['id'],'section'=>section['id'])
output = Portfolio::StaticExport.new(config:cfg, repository:@repo).entries
assert output.key?("#{page['id']}.html")
assert_includes output['index.html'], '수상'
assert_includes output["#{page['id']}.html"], '교내 수상'
assert_includes output["#{page['id']}.html"], "entry-#{custom['id']}.html"
refute_match(/href="\/(?!\/)/, output["#{page['id']}.html"])
```

- [ ] **Step 2: Run the export test and verify RED**

Run: `ruby -Itest test/notebook_test.rb --name test_static_export_is_public_only_and_relative`

Expected: the custom page HTML key is absent because export still iterates the fixed default pages.

- [ ] **Step 3: Snapshot and render the saved navigation**

Add `navigation: notebook_navigation` to the public snapshot. Give `PublicNotebookSnapshot` a `notebook_navigation` reader initialized from the snapshot. Iterate `source.notebook_navigation` when generating static pages, using `page['id']`, `page['title']`, and `Notebook.path(page['id'])`.

Keep the current published-record and public-file filtering unchanged. Do not include administrator state, session state, or private records in the snapshot.

- [ ] **Step 4: Document the new management workflow and persistence rule**

In `README.md`, add `관리자 로그인 → 목차 편집` instructions covering stable URLs, safe deletion, and ordering. In `docs/verification.md`, record the automated checks for navigation CRUD, authorization, dynamic routes, and static export. Keep the existing free Render data-loss warning beside the new instructions.

- [ ] **Step 5: Run the full verification suite**

Run:

```bash
ruby bin/test
git diff --check
git status --short
```

Expected: 0 test failures, 0 test errors, no whitespace errors, and only the planned files modified.

- [ ] **Step 6: Commit the export and documentation changes**

```bash
git add lib/portfolio/static_export.rb test/notebook_test.rb README.md docs/verification.md
git commit -m "Export customized portfolio navigation"
```

---

### Task 5: Review and publish the completed feature

**Files:**
- Review: all files changed since `87ac31a`

**Interfaces:**
- Verifies: repository `main` contains the complete feature with no uncommitted changes
- Publishes: the tested commit sequence to `origin/main`

- [ ] **Step 1: Review scope and security boundaries**

Run:

```bash
git diff --stat 87ac31a..HEAD
git diff 87ac31a..HEAD -- lib/portfolio views public/assets test README.md docs/verification.md
```

Confirm that every mutation is under `/admin`, every POST relies on the existing CSRF gate, all user strings are escaped in ERB, generated IDs are used for paths, and deletion checks happen inside the PStore update transaction.

- [ ] **Step 2: Re-run fresh verification before publishing**

Run:

```bash
ruby bin/test
git diff --check origin/main..HEAD
git status --short --branch
```

Expected: 0 test failures, 0 test errors, no whitespace errors, and `main` is ahead of `origin/main` only by the reviewed commits.

- [ ] **Step 3: Push and verify GitHub**

Run:

```bash
git push origin main
git ls-remote origin refs/heads/main
gh api repos/dawneast1009/portfolio/commits/main --jq '.sha + " " + .commit.message'
```

Expected: the remote `main` SHA equals local `HEAD`, and the GitHub API reports the final navigation feature commit.

- [ ] **Step 4: Verify the Render deployment**

Poll the public home page, `/admin/login`, and `/assets/notebook.css` until the new commit is deployed. Confirm the public site and admin login return 200 and the deployed CSS contains the new `.navigation-card` selector. Ask the user to refresh their existing authenticated browser session and confirm the new `목차 편집` link; do not change or expose the configured administrator password during verification.
