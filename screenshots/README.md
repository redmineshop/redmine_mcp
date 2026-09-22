# Screenshots

PNG files in this folder are captured by the private `redmineshop/redmineshop` plugin quality harness (`demo/e2e/tests/redmine_mcp.spec.js`). Viewport 1440×900, deviceScaleFactor 1, full page. A public clone of this plugin cannot run that compose file.

Expected files after a harness run:

- `mcp-settings.png` — Administration → Plugins → Configure Redmine MCP (no API key on this screen). `plugin-settings.png` is the same image.
- `admin-plugins.png` — Administration → Plugins listing Redmine MCP
- `wiki-agent-notes.png` — wiki page updated through `update_wiki_page` when read-only is off

Not produced here: `mcp-client.png` (no Cursor/Claude window in this harness) and `architecture.png` (no diagram asset).
