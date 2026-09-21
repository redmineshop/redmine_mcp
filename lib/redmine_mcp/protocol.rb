# frozen_string_literal: true

module RedmineMcp
  class ParseError < StandardError; end

  class ToolError < StandardError
    attr_reader :code

    def initialize(message, code: -32000)
      super(message)
      @code = code
    end
  end

  module Protocol
    SUPPORTED_VERSIONS = %w[2024-11-05 2025-03-26 2025-06-18].freeze
    FALLBACK_VERSION = '2024-11-05'

    module_function

    def result(id, value)
      { 'jsonrpc' => '2.0', 'id' => id, 'result' => value }
    end

    def error(id, code, message)
      { 'jsonrpc' => '2.0', 'id' => id, 'error' => { 'code' => code, 'message' => sanitize(message) } }
    end

    def sanitize(message)
      text = message.to_s.gsub(/[A-Za-z0-9_\-]{20,}/, '[redacted]')
      text.gsub(/api[_-]?key[=:]\s*\S+/i, 'api_key=[redacted]')
    end

    def negotiate_version(requested)
      requested = requested.to_s
      SUPPORTED_VERSIONS.include?(requested) ? requested : FALLBACK_VERSION
    end
  end
end
