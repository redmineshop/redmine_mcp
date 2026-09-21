# Screenshots

PNG files in this folder are captured by the private `redmineshop/redmineshop` plugin quality harness (`demo/e2e/tests/redmine_mcp.spec.js`). A public clone of this plugin cannot run that compose file.

Expected files after a harness run:

- `plugin-settings.png` — Administration → Plugins → Configure Redmine MCP
- `admin-plugins.png` — Administration → Plugins listing Redmine MCP
- `wiki-agent-notes.png` — wiki page updated through `update_wiki_page` when read-only is off
