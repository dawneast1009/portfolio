# frozen_string_literal: true
require 'json'
require 'net/http'
require 'openssl'
require 'securerandom'
require 'time'
require 'uri'

module Portfolio
  class PersistenceError < StandardError; end
  class PersistenceConflict < PersistenceError; end
  class PersistenceTransportError < PersistenceError; end

  class SupabaseHttpClient
    def initialize(url:, service_role_key:, transport: nil)
      @base = URI.parse(url.to_s.delete_suffix('/'))
      raise PersistenceError, 'SUPABASE_URL은 HTTPS 주소여야 합니다' unless @base.scheme == 'https' && @base.host
      @key = service_role_key.to_s
      raise PersistenceError, 'SUPABASE_SERVICE_ROLE_KEY가 비어 있습니다' if @key.empty?
      @transport = transport
    rescue URI::InvalidURIError
      raise PersistenceError, 'SUPABASE_URL이 올바르지 않습니다'
    end

    private

    def request(method, path, body: nil, headers: {})
      uri = @base + path
      merged = { 'Authorization' => "Bearer #{@key}", 'apikey' => @key }.merge(headers)
      return @transport.call(method: method, uri: uri, headers: merged, body: body) if @transport

      request = method.new(uri)
      merged.each { |key, value| request[key] = value }
      request.body = body if body
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError => e
      raise PersistenceTransportError, "Supabase에 연결할 수 없습니다 (#{e.class})"
    end

    def expect_success(response, service: 'Supabase')
      return response if response.code.to_i.between?(200, 299)
      raise PersistenceError, "#{service} 요청이 실패했습니다 (HTTP #{response.code})"
    end

    def parse_json(response, service: 'Supabase')
      expect_success(response, service: service)
      JSON.parse(response.body.to_s, create_additions: false)
    rescue JSON::ParserError
      raise PersistenceError, "#{service} 응답 형식이 올바르지 않습니다"
    end
  end

  class SupabaseObjectClient < SupabaseHttpClient
    def initialize(url:, service_role_key:, bucket:, transport: nil)
      super(url: url, service_role_key: service_role_key, transport: transport)
      @bucket = bucket.to_s
      raise PersistenceError, 'SUPABASE_BUCKET이 올바르지 않습니다' unless @bucket.match?(/\A[a-z0-9][a-z0-9._-]{0,62}\z/)
    end

    def download(path, cache_bust: false)
      encoded = path.split('/').map { |part| URI.encode_www_form_component(part) }.join('/')
      query = cache_bust ? "?v=#{URI.encode_www_form_component(SecureRandom.hex(8))}" : ''
      response = request(Net::HTTP::Get, "/storage/v1/object/#{URI.encode_www_form_component(@bucket)}/#{encoded}#{query}",
        headers: { 'Cache-Control' => 'no-cache' })
      return nil if response.code.to_i == 404
      expect_success(response, service: 'Supabase Storage')
      response.body.to_s.b
    end

    def upload(path, bytes, content_type: 'application/octet-stream')
      encoded = path.split('/').map { |part| URI.encode_www_form_component(part) }.join('/')
      response = request(Net::HTTP::Post, "/storage/v1/object/#{URI.encode_www_form_component(@bucket)}/#{encoded}",
        body: bytes, headers: { 'Content-Type' => content_type, 'x-upsert' => 'true', 'cache-control' => 'no-store' })
      expect_success(response, service: 'Supabase Storage')
    end

    def delete(path)
      encoded = path.split('/').map { |part| URI.encode_www_form_component(part) }.join('/')
      response = request(Net::HTTP::Delete, "/storage/v1/object/#{URI.encode_www_form_component(@bucket)}/#{encoded}")
      return if response.code.to_i == 404
      expect_success(response, service: 'Supabase Storage')
    end
  end

  class SupabaseDatabaseClient < SupabaseHttpClient
    TABLE_PATH = '/rest/v1/portfolio_state'

    def restore_state
      response = request(Net::HTTP::Get, "#{TABLE_PATH}?id=eq.singleton&select=revision,state",
        headers: { 'Accept' => 'application/json', 'Cache-Control' => 'no-cache' })
      raise PersistenceError, 'Supabase Database 테이블을 찾을 수 없습니다. supabase/schema.sql을 먼저 실행해 주세요' if response.code.to_i == 404
      rows = parse_json(response, service: 'Supabase Database')
      return nil if rows.empty?
      row = rows.first
      revision = Integer(row.fetch('revision'))
      raise PersistenceError, 'Supabase Database의 revision이 올바르지 않습니다' if revision < 1
      { 'state' => row.fetch('state'), 'revision' => revision }
    rescue KeyError, TypeError, ArgumentError
      raise PersistenceError, 'Supabase Database의 상태 형식이 올바르지 않습니다'
    end

    def save_state(state, expected_revision:)
      if expected_revision.nil?
        response = request(Net::HTTP::Post, TABLE_PATH,
          body: JSON.generate([{ 'id' => 'singleton', 'revision' => 1, 'state' => state }]),
          headers: json_headers.merge('Prefer' => 'return=representation'))
        raise PersistenceConflict, 'Supabase 상태가 이미 존재합니다. 페이지를 새로고침해 주세요' if response.code.to_i == 409
        row = first_row(parse_json(response, service: 'Supabase Database'))
        return Integer(row.fetch('revision'))
      end

      expected = Integer(expected_revision)
      response = request(Net::HTTP::Patch,
        "#{TABLE_PATH}?id=eq.singleton&revision=eq.#{expected}&select=revision",
        body: JSON.generate({ 'revision' => expected + 1, 'state' => state,
          'updated_at' => Time.now.utc.iso8601 }),
        headers: json_headers.merge('Prefer' => 'return=representation'))
      rows = parse_json(response, service: 'Supabase Database')
      raise PersistenceConflict, 'Supabase 상태가 다른 곳에서 변경됐습니다. 페이지를 새로고침해 주세요' if rows.empty?
      Integer(rows.first.fetch('revision'))
    rescue KeyError, TypeError, ArgumentError
      raise PersistenceError, 'Supabase Database의 상태 형식이 올바르지 않습니다'
    end

    private

    def json_headers
      { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    end

    def first_row(rows)
      raise PersistenceError, 'Supabase Database가 저장 결과를 반환하지 않았습니다' unless rows.is_a?(Array) && rows.first.is_a?(Hash)
      rows.first
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

    MAX_STATE_BYTES = 40 * 1024 * 1024

    def initialize(url:, service_role_key:, bucket: 'portfolio-data', client: nil, database: nil)
      @bucket = bucket
      @client = client || SupabaseObjectClient.new(url: url, service_role_key: service_role_key, bucket: bucket)
      @database = database || SupabaseDatabaseClient.new(url: url, service_role_key: service_role_key)
    end

    def restore_state
      result = @database.restore_state
      return nil unless result
      validate_state!(result.fetch('state'))
      revision = Integer(result.fetch('revision'))
      raise PersistenceError, 'Supabase Database의 revision이 올바르지 않습니다' if revision < 1
      { 'state' => result.fetch('state'), 'revision' => revision }
    rescue KeyError, TypeError, ArgumentError
      raise PersistenceError, 'Supabase Database의 상태 형식이 올바르지 않습니다'
    end

    def save_state(state, expected_revision:)
      validate_state!(state)
      raise PersistenceError, '포트폴리오 상태가 너무 큽니다 (최대 40MB)' if JSON.generate(state).bytesize > MAX_STATE_BYTES
      @database.save_state(state, expected_revision: expected_revision)
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

    private

    def validate_state!(state)
      required = %w[schema_version profile admin projects files messages]
      unless state.is_a?(Hash) && state['schema_version'] == 1 && required.all? { |key| state.key?(key) } &&
          state['profile'].is_a?(Hash) && state['projects'].is_a?(Hash) && state['files'].is_a?(Hash) && state['messages'].is_a?(Hash)
        raise PersistenceError, 'Supabase의 포트폴리오 상태 형식이 올바르지 않습니다'
      end
    end
  end
end
