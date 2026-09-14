# frozen_string_literal: true
require 'json'
require 'net/http'
require 'uri'

module Portfolio
  class PersistenceError < StandardError; end

  class SupabaseObjectClient
    def initialize(url:, service_role_key:, bucket:)
      @base = URI.parse(url.to_s.delete_suffix('/'))
      raise PersistenceError, 'SUPABASE_URL은 HTTPS 주소여야 합니다' unless @base.scheme == 'https' && @base.host
      @key = service_role_key.to_s
      raise PersistenceError, 'SUPABASE_SERVICE_ROLE_KEY가 비어 있습니다' if @key.empty?
      @bucket = bucket.to_s
      raise PersistenceError, 'SUPABASE_BUCKET이 올바르지 않습니다' unless @bucket.match?(/\A[a-z0-9][a-z0-9._-]{0,62}\z/)
    rescue URI::InvalidURIError
      raise PersistenceError, 'SUPABASE_URL이 올바르지 않습니다'
    end

    def download(path)
      response = request(Net::HTTP::Get, path)
      return nil if response.code.to_i == 404
      expect_success(response)
      response.body.to_s.b
    end

    def upload(path, bytes, content_type: 'application/octet-stream')
      response = request(Net::HTTP::Post, path, body: bytes, content_type: content_type,
        extra: { 'x-upsert' => 'true' })
      expect_success(response)
    end

    def delete(path)
      response = request(Net::HTTP::Delete, path)
      return if response.code.to_i == 404
      expect_success(response)
    end

    private

    def request(method, path, body: nil, content_type: nil, extra: {})
      encoded = path.split('/').map { |part| URI.encode_www_form_component(part) }.join('/')
      uri = @base + "/storage/v1/object/#{URI.encode_www_form_component(@bucket)}/#{encoded}"
      request = method.new(uri)
      request['Authorization'] = "Bearer #{@key}"
      request['apikey'] = @key
      request['Content-Type'] = content_type if content_type
      extra.each { |key, value| request[key] = value }
      request.body = body if body
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end
    rescue Timeout::Error, SocketError, SystemCallError, IOError => e
      raise PersistenceError, "Supabase Storage에 연결할 수 없습니다 (#{e.class})"
    end

    def expect_success(response)
      return response if response.is_a?(Net::HTTPSuccess)
      raise PersistenceError, "Supabase Storage 요청이 실패했습니다 (HTTP #{response.code})"
    end
  end

  class SupabasePersistence
    attr_reader :bucket

    def self.from_env(env)
      url = env['SUPABASE_URL'].to_s.strip
      key = env['SUPABASE_SERVICE_ROLE_KEY'].to_s.strip
      return nil if url.empty? && key.empty?
      raise PersistenceError, 'SUPABASE_URL과 SUPABASE_SERVICE_ROLE_KEY를 함께 설정해 주세요' if url.empty? || key.empty?
      new(url: url, service_role_key: key, bucket: env.fetch('SUPABASE_BUCKET', 'portfolio-data'))
    end

    def initialize(url:, service_role_key:, bucket: 'portfolio-data', client: nil)
      @bucket = bucket
      @client = client || SupabaseObjectClient.new(url: url, service_role_key: service_role_key, bucket: bucket)
    end

    def restore_state
      bytes = @client.download('state.json')
      return nil unless bytes
      JSON.parse(bytes, create_additions: false)
    rescue JSON::ParserError
      raise PersistenceError, 'Supabase의 state.json 형식이 올바르지 않습니다'
    end

    def save_state(state)
      @client.upload('state.json', JSON.generate(state), content_type: 'application/json')
    end

    def upload_file(id, bytes)
      @client.upload("files/#{id}.blob", bytes)
    end

    def download_file(id)
      @client.download("files/#{id}.blob")
    end

    def delete_file(id)
      @client.delete("files/#{id}.blob")
    end
  end
end
