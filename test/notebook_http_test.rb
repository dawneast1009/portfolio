# frozen_string_literal: true
require_relative 'http_test'

class HttpTest
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
