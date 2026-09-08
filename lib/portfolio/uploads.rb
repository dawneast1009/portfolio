# frozen_string_literal: true
require_relative 'security'

module Portfolio
  module Uploads
    EXTENSIONS = %w[.pdf .png .jpg .jpeg .webp .txt .md .zip .hwp .hwpx .docx .pptx .xlsx].freeze
    IMAGE_MIMES = %w[image/png image/jpeg image/webp].freeze
    module_function

    def inspect_file(filename, bytes, max_bytes:)
      raise ValidationError, '파일을 선택해 주세요' unless filename.is_a?(String) && bytes.is_a?(String)
      name = filename.dup.force_encoding(Encoding::UTF_8)
      raise ValidationError, '올바른 UTF-8 파일 이름이 필요합니다' unless name.valid_encoding?
      name = name.tr('\\', '/').split('/').last.to_s
      if name.empty? || name.bytesize > 200 || name.match?(/[\x00-\x1f\x7f]/)
        raise ValidationError, '파일 이름이 비어 있거나 너무 길거나 허용되지 않는 문자가 있습니다'
      end
      ext = File.extname(name).downcase
      raise ValidationError, 'PDF, 이미지, TXT, MD, ZIP, HWP, HWPX, DOCX, PPTX, XLSX 파일만 업로드할 수 있습니다' unless EXTENSIONS.include?(ext)
      raise ValidationError, '빈 파일은 업로드할 수 없습니다' if bytes.empty?
      raise ValidationError, '파일이 업로드 용량 제한을 초과했습니다' if bytes.bytesize > max_bytes
      binary = bytes.b
      mime = case ext
             when '.pdf'
               'application/pdf' if binary.match?(/\A%PDF-[12]\.\d/n) && binary.byteslice(-2048, 2048).to_s.include?('%%EOF') ||
                 (binary.bytesize < 2048 && binary.match?(/\A%PDF-[12]\.\d/n) && binary.include?('%%EOF'))
             when '.png'
               'image/png' if binary.start_with?("\x89PNG\r\n\x1a\n".b) && binary.bytesize >= 33 && binary.byteslice(12, 4) == 'IHDR'
             when '.jpg', '.jpeg'
               'image/jpeg' if binary.start_with?("\xff\xd8\xff".b) && binary.end_with?("\xff\xd9".b)
             when '.webp'
               'image/webp' if binary.bytesize >= 20 && binary.start_with?('RIFF') && binary.byteslice(8, 4) == 'WEBP'
             when '.hwp'
               'application/x-hwp' if binary.bytesize >= 512 && binary.start_with?("\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1".b)
             when '.docx', '.pptx', '.xlsx', '.hwpx'
               types = { '.docx'=>'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                 '.pptx'=>'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                 '.xlsx'=>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.hwpx'=>'application/hwp+zip' }
               types[ext] if binary.bytesize >= 22 && binary.start_with?("PK\x03\x04".b)
             when '.zip'
               'application/zip' if binary.bytesize >= 22 && ["PK\x03\x04".b, "PK\x05\x06".b].any? { |magic| binary.start_with?(magic) }
             when '.txt', '.md'
               text = bytes.dup.force_encoding(Encoding::UTF_8)
               'text/plain' if text.valid_encoding? && !text.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
             end
      raise ValidationError, '확장자와 파일 내용이 일치하지 않거나 지원하지 않는 파일입니다' unless mime
      { 'filename' => name, 'extension' => ext.delete_prefix('.'), 'mime' => mime, 'size' => bytes.bytesize }
    end
  end
end
