# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpSettingsTest < ActiveSupport::TestCase
  def setup
    Setting.plugin_redmine_mcp = RedmineMcp::Settings::DEFAULTS.dup
  end

  def teardown
    Setting.plugin_redmine_mcp = RedmineMcp::Settings::DEFAULTS.dup
  end

  def test_defaults_are_off_and_read_only
    assert_not RedmineMcp::Settings.enabled?
    assert RedmineMcp::Settings.read_only?
    assert_equal 25, RedmineMcp::Settings.max_results
  end

  def test_enabled_reads_checkbox
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '1', 'max_results' => '10' }
    assert RedmineMcp::Settings.enabled?
    assert RedmineMcp::Settings.read_only?
    assert_equal 10, RedmineMcp::Settings.max_results
  end

  def test_max_results_caps_at_absolute_maximum
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '0', 'max_results' => '999' }
    assert_not RedmineMcp::Settings.read_only?
    assert_equal RedmineMcp::Settings::ABSOLUTE_MAX_RESULTS, RedmineMcp::Settings.max_results
  end

  def test_invalid_max_results_falls_back
    Setting.plugin_redmine_mcp = { 'max_results' => '0' }
    assert_equal RedmineMcp::Settings::DEFAULT_MAX_RESULTS, RedmineMcp::Settings.max_results
  end
end
