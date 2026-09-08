# frozen_string_literal: true
require 'openssl'
require 'securerandom'
require 'digest'
require 'thread'

module Portfolio
  class ValidationError < StandardError; end
  class NotFound < StandardError; end

  module Security
    ITERATIONS = 600_000
    module_function

    def constant_compare(a, b)
      a.is_a?(String) && b.is_a?(String) && a.bytesize == b.bytesize &&
        !a.empty? && OpenSSL.fixed_length_secure_compare(a, b)
    end

    def hash_password(password)
      unless password.is_a?(String) && password.length >= 15 && password.bytesize <= 256
        raise ValidationError, '비밀번호는 15자 이상, 256바이트 이하로 입력해 주세요'
      end
      salt = SecureRandom.hex(16)
      digest = OpenSSL::KDF.pbkdf2_hmac(password, salt: [salt].pack('H*'),
        iterations: ITERATIONS, length: 32, hash: 'sha256').unpack1('H*')
      { 'algorithm' => 'pbkdf2-sha256', 'iterations' => ITERATIONS, 'salt' => salt, 'digest' => digest }
    end

    def verify_password(password, record)
      return false unless password.is_a?(String) && password.bytesize <= 256 && record.is_a?(Hash)
      return false unless record['algorithm'] == 'pbkdf2-sha256' && record['iterations'] == ITERATIONS
      return false unless record['salt'].to_s.match?(/\A[0-9a-f]{32}\z/) && record['digest'].to_s.match?(/\A[0-9a-f]{64}\z/)
      derived = OpenSSL::KDF.pbkdf2_hmac(password, salt: [record['salt']].pack('H*'),
        iterations: ITERATIONS, length: 32, hash: 'sha256').unpack1('H*')
      constant_compare(derived, record['digest'])
    end
  end

  # Opaque tokens live in the cookie; authentication state never does.
  # In-memory sessions are deliberately revoked when the process restarts.
  class Sessions
    IDLE_TTL = 3600
    ABSOLUTE_TTL = 8 * 3600
    MAX_ENTRIES = 2000

    def initialize
      @entries = {}
      @mutex = Mutex.new
    end

    def create(admin_version: nil)
      @mutex.synchronize do
        prune
        if @entries.size >= MAX_ENTRIES
          oldest = @entries.find { |_key, value| value['admin_version'].nil? }
          @entries.delete(oldest ? oldest.first : @entries.keys.first)
        end
        token = SecureRandom.hex(32)
        data = { 'csrf' => SecureRandom.hex(32), 'created_at' => now,
          'last_seen' => now, 'admin_version' => admin_version }
        @entries[key(token)] = data
        [token, data.dup]
      end
    end

    def lookup(token)
      return nil unless token.to_s.match?(/\A[0-9a-f]{64}\z/)
      @mutex.synchronize do
        entry = @entries[key(token)]
        return nil unless entry
        if expired?(entry)
          @entries.delete(key(token))
          return nil
        end
        entry['last_seen'] = now
        entry.dup
      end
    end

    def rotate(token, admin_version: nil)
      delete(token)
      create(admin_version: admin_version)
    end

    def delete(token)
      @mutex.synchronize { @entries.delete(key(token)) }
    end

    def set_flash(token, message)
      @mutex.synchronize do
        entry = @entries[key(token)]
        entry['flash'] = message if entry
      end
    end

    def take_flash(token)
      @mutex.synchronize { @entries[key(token)]&.delete('flash') }
    end

    private

    def key(token) = Digest::SHA256.hexdigest(token.to_s)
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    def expired?(entry) = now - entry['last_seen'] > IDLE_TTL || now - entry['created_at'] > ABSOLUTE_TTL
    def prune = @entries.delete_if { |_key, value| expired?(value) }
  end

  # Fixed windows with a hard bound on memory. Reverse-proxy deployments
  # should also rate-limit at the proxy; forwarded IP headers are not trusted.
  class RateLimiter
    def initialize
      @entries = {}
      @mutex = Mutex.new
    end

    def allow?(key, limit:, window:)
      @mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @entries.delete_if { |_name, value| value[:expires] <= now }
        return false if !@entries.key?(key) && @entries.size >= 4096
        entry = (@entries[key] ||= { count: 0, expires: now + window })
        return false if entry[:count] >= limit
        entry[:count] += 1
        true
      end
    end
  end
end
