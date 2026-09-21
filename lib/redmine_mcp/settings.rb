# frozen_string_literal: true

module RedmineMcp
  class Settings
    DEFAULTS = {
      'enabled' => '0',
      'read_only' => '1',
      'max_results' => '25'
    }.freeze

    DEFAULT_MAX_RESULTS = 25
    ABSOLUTE_MAX_RESULTS = 50

    class << self
      def raw
        stored = Setting.plugin_redmine_mcp
        DEFAULTS.merge(stored.is_a?(Hash) ? stored.stringify_keys : {})
      end

      def enabled?
        raw['enabled'].to_s == '1'
      end

      def read_only?
        raw['read_only'].to_s != '0'
      end

      def max_results
        value = raw['max_results'].to_i
        value = DEFAULT_MAX_RESULTS if value <= 0
        [value, ABSOLUTE_MAX_RESULTS].min
      end
    end
  end
end
