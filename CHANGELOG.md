# Changelog — Redmine MCP

All notable changes to this plugin.

## [1.0.0] — 2026-09-21

First Community release. Free forever, no license key, no phone-home.

### Added

- HTTP MCP endpoint `POST /mcp` (JSON-RPC 2.0, off until an admin enables it)
- API-key authentication (`X-Redmine-API-Key`, `Authorization: Bearer`, or `?key=`)
- Read-only mode on by default; write tools hidden from `tools/list`
- Read tools: `whoami`, `list_projects`, `get_project`, `search_issues`, `get_issue`, `list_enumerations`, `list_custom_fields`, `list_users`, `list_wiki_pages`, `get_wiki_page`
- Write tool (when read-only is off): `update_wiki_page`
- Result cap (default 25, absolute 50)
- English + Vietnamese settings strings
- MiniTest unit + functional HTTP coverage

[1.0.0]: https://github.com/redmineshop/redmine_mcp
