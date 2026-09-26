# frozen_string_literal: true

require 'redmine'

require_relative 'lib/redmine_mcp/version'
require_relative 'lib/redmine_mcp/settings'
require_relative 'lib/redmine_mcp/protocol'
require_relative 'lib/redmine_mcp/tool_registry'
require_relative 'lib/redmine_mcp/runbook_tools'
require_relative 'lib/redmine_mcp/tools'
require_relative 'lib/redmine_mcp/server'

Redmine::Plugin.register :redmine_mcp do
  name 'Redmine MCP'
  author 'RedmineShop'
  author_url 'https://redmineshop.com'
  description 'MCP server inside Redmine — Cursor, Claude Desktop, and Cloud Agent use a Redmine API key. Community edition, free forever.'
  version RedmineMcp::VERSION
  url 'https://github.com/redmineshop/redmine_mcp'

  requires_redmine version_or_higher: '5.1'

  settings default: RedmineMcp::Settings::DEFAULTS,
           partial: 'settings/mcp_settings'
end
