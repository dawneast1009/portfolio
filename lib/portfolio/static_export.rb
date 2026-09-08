# frozen_string_literal: true
require 'zlib'
require_relative 'config'
require_relative 'repository'
require_relative 'view'

module Portfolio
  # A single read transaction creates an isolated, public-only view for export.
  class Repository
    def public_notebook_snapshot
      state = @store.read
      records = state['projects'].values.select { |r| r['status'] == 'published' }
      ids = records.map { |r| r['id'] }
      attachments = state['files'].values.select { |f| f['public'] && (ids.include?(f['project_id']) || (f['id'] == state['profile']['resume_id'] && public_in_state?(f,state))) }
      { profile:state['profile'], projects:records, files:attachments }
    end
  end

  class PublicNotebookSnapshot
    include NotebookRepository
    attr_reader :profile, :projects, :files
    def initialize(snapshot)
      @profile, @projects, @files = snapshot.values_at(:profile,:projects,:files)
      @file_index = @files.to_h { |f| [f['id'],f] }
    end
    def file(id) = @file_index[id]
    def public_file?(record) = !!(record && @file_index.key?(record['id']))
  end

  class StaticExport
    MAX_BYTES = 64 * 1024 * 1024
    def initialize(config:, repository:)
      @config, @repository = config, repository
    end

    def entries
      source = PublicNotebookSnapshot.new(@repository.public_notebook_snapshot)
      raise ValidationError, '내보낼 파일은 합계 64 MiB 이하로 줄여 주세요' if source.files.sum { |f| f['size'] } > MAX_BYTES
      raise ValidationError, '한 번에 내보낼 수 있는 기록은 2,000개입니다' if source.projects.size > 2000
      output = {}
      Notebook::PAGES.each do |key, page|
        name = key == 'home' ? 'index.html' : "#{key}.html"
        output[name] = render(source,'notebook/page',Notebook.path(key),page[:title],page_key:key)
      end
      source.projects.each do |record|
        output["entry-#{record['id']}.html"] = render(source,'notebook/entry',"/entry/#{record['id']}",record['title'],
          record:record,page_key:Notebook.page_of(record))
      end
      source.files.each do |file|
        path = @repository.file_path(file)
        raise ValidationError, "첨부파일을 찾을 수 없습니다: #{file['filename']}" unless File.file?(path)
        output["files/#{file['id']}.#{file['extension']}"] = File.binread(path)
      end
      %w[notebook.css app.js favicon.svg].each do |asset|
        output["assets/#{asset}"] = File.binread(File.join(@config.root,'public','assets',asset))
      end
      output['.nojekyll'] = ''
      output['README-제출.txt'] = "공개한 기록과 첨부파일만 포함한 읽기 전용 포트폴리오입니다.\nindex.html을 열어 확인할 수 있습니다.\nGitHub Pages 또는 정적 사이트에 이 폴더의 내용을 올리고 실제 배포 주소를 제출하세요.\n파일을 열기만 한 file:// 주소나 localhost 주소는 공유할 수 없습니다.\n이 ZIP은 편집 데이터의 백업이 아닙니다. 원본 Ruby 프로젝트의 storage 폴더도 따로 보관하세요.\n"
      raise ValidationError, '완성된 제출본이 64 MiB를 넘었습니다. 첨부파일을 줄여 주세요' if output.values.sum(&:bytesize) > MAX_BYTES
      output
    end

    def archive
      # ZIP "stored" entries (no decompression or shell invocation). UTF-8 names,
      # fixed 1980-01-01 timestamps, CRC32; interoperability tested with zipfile/unzip.
      body, central = +''.b, +''.b
      items = entries
      items.each do |path, bytes|
        name, data = path.encode(Encoding::UTF_8).b, bytes.b
        offset, size, crc = body.bytesize, data.bytesize, Zlib.crc32(data)
        body << [0x04034b50,20,0x800,0,0,33,crc,size,size,name.bytesize,0].pack('VvvvvvVVVvv') << name << data
        central << [0x02014b50,20,20,0x800,0,0,33,crc,size,size,name.bytesize,0,0,0,0,0,offset].pack('VvvvvvvVVVvvvvvVV') << name
      end
      offset = body.bytesize
      body << central << [0x06054b50,0,0,items.size,items.size,central.bytesize,offset,0].pack('VvvvvVVv')
    end

    private
    def render(repository,template,path,title,**data)
      View.new(config:@config,repository:repository,path:path,authenticated:false,csrf:nil,flash:nil,title:title,
        data:data.merge(static:true)).render(template)
    end
  end
end
