# frozen_string_literal: true
require_relative 'http_test'

class HttpTest
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

  def test_navigation_manager_updates_moves_and_deletes_empty_items
    token = login
    page = @repo.save_notebook_page({'title'=>'수상','description'=>'','icon'=>'folder'})
    updated = request('POST',"/admin/navigation/pages/#{page['id']}",
      form:{'_csrf'=>token,'title'=>'수상 및 자격','description'=>'도전의 결과','icon'=>'file'})
    assert_equal '303', updated.code
    assert_equal '수상 및 자격', Portfolio::Notebook.page(@repo.notebook_navigation,page['id'])['title']

    created = request('POST',"/admin/navigation/pages/#{page['id']}/sections",
      form:{'_csrf'=>token,'title'=>'교내 수상'})
    assert_equal '303', created.code
    first = Portfolio::Notebook.page(@repo.notebook_navigation,page['id'])['sections'].first
    second = @repo.save_notebook_section(page['id'], {'title'=>'교외 수상'})
    moved = request('POST',"/admin/navigation/pages/#{page['id']}/sections/#{second['id']}/move",
      form:{'_csrf'=>token,'direction'=>'up'})
    assert_equal '303', moved.code
    assert_equal second['id'], Portfolio::Notebook.page(@repo.notebook_navigation,page['id'])['sections'].first['id']

    renamed = request('POST',"/admin/navigation/pages/#{page['id']}/sections/#{first['id']}",
      form:{'_csrf'=>token,'title'=>'학교 수상'})
    assert_equal '303', renamed.code
    assert_equal '학교 수상', Portfolio::Notebook.section(Portfolio::Notebook.page(@repo.notebook_navigation,page['id']),first['id'])['title']
    assert_equal '303', request('POST',"/admin/navigation/pages/#{page['id']}/sections/#{first['id']}/delete",
      form:{'_csrf'=>token}).code
    assert_equal '303', request('POST',"/admin/navigation/pages/#{page['id']}/move",
      form:{'_csrf'=>token,'direction'=>'up'}).code
    assert_equal '303', request('POST',"/admin/navigation/pages/#{page['id']}/delete", form:{'_csrf'=>token}).code
    refute Portfolio::Notebook.page(@repo.notebook_navigation,page['id'])
  end

  def test_navigation_manager_renders_deletion_errors_without_losing_records
    token = login
    record = @repo.save_entry({'title'=>'강점 기록','body'=>'내용','page'=>'about','section'=>'strengths','status'=>'published','level'=>''})
    blocked = request('POST','/admin/navigation/pages/about/sections/strengths/delete', form:{'_csrf'=>token})
    assert_equal '422', blocked.code
    assert_includes blocked.body.force_encoding('UTF-8'), '연결된 기록'
    assert_equal record['id'], @repo.notebook_entries('about',section:'strengths').first['id']
    home = request('POST','/admin/navigation/pages/home/delete', form:{'_csrf'=>token})
    assert_equal '422', home.code
    assert_includes home.body.force_encoding('UTF-8'), '홈 메뉴는 삭제할 수 없습니다'
  end

  def test_custom_navigation_drives_public_pages_and_record_editor
    login
    page = @repo.save_notebook_page({'title'=>'수상','description'=>'도전의 결과','icon'=>'folder'})
    section = @repo.save_notebook_section(page['id'], {'title'=>'교내 수상'})
    item = @repo.save_entry({'title'=>'과학상','body'=>'탐구 결과','page'=>page['id'],
      'section'=>section['id'],'status'=>'published','level'=>''})
    public_page = request('GET', "/#{page['id']}", cookie:false)
    assert_equal '200', public_page.code
    assert_includes public_page.body.force_encoding('UTF-8'), '도전의 결과'
    assert_includes public_page.body.force_encoding('UTF-8'), '과학상'
    home = request('GET','/',cookie:false).body.force_encoding('UTF-8')
    assert_includes home, '수상'
    assert_includes home, '교내 수상'
    refute_includes home, '/admin/navigation'
    editor = request('GET', "/admin/notebook/#{item['id']}/edit")
    assert_equal '200', editor.code
    assert_includes editor.body.force_encoding('UTF-8'), '교내 수상'
    assert_includes request('GET','/admin/navigation').body.force_encoding('UTF-8'), '목차 관리'
  end

  def test_navigation_title_changes_keep_existing_public_route
    @repo.save_notebook_page({'title'=>'나에 대하여','description'=>'새 소개','icon'=>'user'}, id:'about')
    response = request('GET','/about',cookie:false)
    assert_equal '200', response.code
    assert_includes response.body.force_encoding('UTF-8'), '나에 대하여'
    assert_equal '404', request('GET','/page-000000000000',cookie:false).code
    @repo.delete_notebook_page('about')
    assert_equal '404', request('GET','/about',cookie:false).code
  end

  def test_notebook_five_pages_show_correct_sections
    { '/' => '포트폴리오', '/about'=>'가치관', '/career'=>'관심 직업', '/activities'=>'사용 프로그램 및 숙련도', '/projects'=>'주제탐구보고서' }.each do |path, text|
      response = request('GET', path)
      assert_equal '200', response.code, path
      assert_includes response.body.force_encoding('UTF-8'), text
      assert_includes response.body, 'aria-label="포트폴리오 메뉴"'
    end
  end
  def test_notebook_editor_requires_login_and_csrf
    assert_equal '303', request('GET','/admin/notebook/new?page=about&section=strengths').code
    token = login
    page = request('GET','/admin/notebook/new?page=about&section=strengths')
    assert_equal '200', page.code
    assert_equal '403', request('POST','/admin/notebook', form:{'title'=>'몰래 변경'}).code
    response = request('POST','/admin/notebook',form:{'_csrf'=>token,'title'=>'강점 기록','body'=>'나의 글','page'=>'about','section'=>'strengths','status'=>'published','level'=>''})
    assert_equal '303', response.code
    record = @repo.projects.first
    assert_equal '강점 기록', record['title']
    assert_includes request('GET','/about',cookie:false).body.force_encoding('UTF-8'), '강점 기록'
  end
  def test_notebook_error_retains_form_values_and_rejects_invalid_section
    token = login
    response = request('POST','/admin/notebook',form:{'_csrf'=>token,'title'=>'내용 유지','body'=>'원래 쓴 본문','page'=>'career','section'=>'strengths','status'=>'published'})
    assert_equal '422', response.code
    assert_includes response.body.force_encoding('UTF-8'), '원래 쓴 본문'
    assert_empty @repo.projects
  end
  def test_notebook_anonymous_export_denied
    assert_equal '303', request('GET','/admin/export.zip').code
  end
  def test_notebook_draft_detail_private_and_content_escaped
    token = login
    response = request('POST','/admin/notebook', form:{'_csrf'=>token,'title'=>'초안','body'=>'<script>bad()</script>','page'=>'projects','section'=>'reading','status'=>'draft'})
    assert_equal '303', response.code
    item = @repo.projects.first
    assert_equal '404', request('GET',"/entry/#{item['id']}",cookie:false).code
    assert_equal '200', request('GET',"/entry/#{item['id']}").code
    assert_includes request('GET',"/entry/#{item['id']}").body, '&lt;script&gt;bad()&lt;/script&gt;'
    refute_includes request('GET','/projects',cookie:false).body.force_encoding('UTF-8'), '초안'
  end
  def test_notebook_attachment_upload_and_export_zip
    token = login
    response = request('POST','/admin/notebook', form:{'_csrf'=>token,'title'=>'보고서','body'=>'탐구','page'=>'projects','section'=>'report','status'=>'published'})
    assert_equal '303', response.code
    id = @repo.projects.first['id']
    boundary = 'SchoolNotebookUpload123'
    fields = { '_csrf'=>token, 'project_id'=>id, 'public'=>'1' }.map { |k,v| "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{k}\"\r\n\r\n#{v}\r\n" }.join
    body = fields + "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"한글자료.txt\"\r\nContent-Type: text/plain\r\n\r\nfile contents\r\n--#{boundary}--\r\n"
    uploaded = request('POST','/admin/notebook-upload',headers:{'Content-Type'=>"multipart/form-data; boundary=#{boundary}"},body:body)
    assert_equal '303', uploaded.code
    f = @repo.files.first
    assert_equal 'file contents', request('GET',"/files/#{f['id']}/download",cookie:false).body
    zip = request('GET','/admin/export.zip')
    assert_equal '200', zip.code
    assert_equal 'application/zip', zip['content-type']
    assert zip.body.b.start_with?("PK\x03\x04".b)
    assert_includes zip.body.b, 'index.html'.b
    refute_includes zip.body.b, PASSWORD.b
  end
end
