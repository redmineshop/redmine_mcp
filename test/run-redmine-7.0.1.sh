#!/usr/bin/env bash
# Run this plugin's tests inside the official redmine:7.0.1 image (SQLite).
# The image omits the Gemfile :test group; this script installs it.
# When Issue Templates and Issue Checklists are available (sibling directories
# or TEMPLATES_PLUGIN_DIR / CHECKLISTS_PLUGIN_DIR), they are mounted so
# template and checklist tools run against the real plugins.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${REDMINE_IMAGE:-redmine:7.0.1}"
TEMPLATES="${TEMPLATES_PLUGIN_DIR:-}"
CHECKLISTS="${CHECKLISTS_PLUGIN_DIR:-}"

if [[ -z "$TEMPLATES" && -f "$PLUGIN_DIR/../redmine_issue_templates/init.rb" ]]; then
  TEMPLATES="$PLUGIN_DIR/../redmine_issue_templates"
fi
if [[ -z "$CHECKLISTS" && -f "$PLUGIN_DIR/../redmine_issue_checklists/init.rb" ]]; then
  CHECKLISTS="$PLUGIN_DIR/../redmine_issue_checklists"
fi

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
fi

MOUNTS=(-v "$PLUGIN_DIR:/opt/plugin:ro")
if [[ -n "$TEMPLATES" && -f "$TEMPLATES/init.rb" ]]; then
  echo "Including Issue Templates from ${TEMPLATES}"
  MOUNTS+=(-v "$TEMPLATES:/opt/templates:ro")
else
  echo "Issue Templates is not mounted. Template tool tests skip."
fi
if [[ -n "$CHECKLISTS" && -f "$CHECKLISTS/init.rb" ]]; then
  echo "Including Issue Checklists from ${CHECKLISTS}"
  MOUNTS+=(-v "$CHECKLISTS:/opt/checklists:ro")
else
  echo "Issue Checklists is not mounted. Checklist tool tests skip."
fi

"${DOCKER[@]}" run --rm --user root \
  -e SECRET_KEY_BASE=redmine-mcp-test-secret \
  -e REDMINE_LANG=en \
  "${MOUNTS[@]}" \
  --entrypoint bash \
  "$IMAGE" \
  -lc 'set -euo pipefail
cd /usr/src/redmine
rm -rf plugins/redmine_mcp plugins/redmine_issue_templates plugins/redmine_issue_checklists
cp -a /opt/plugin plugins/redmine_mcp
if [[ -f /opt/templates/init.rb ]]; then
  cp -a /opt/templates plugins/redmine_issue_templates
fi
if [[ -f /opt/checklists/init.rb ]]; then
  cp -a /opt/checklists plugins/redmine_issue_checklists
fi
mkdir -p db tmp log
cat > config/database.yml <<YAML
production:
  adapter: sqlite3
  database: db/redmine.sqlite3
development:
  adapter: sqlite3
  database: db/redmine_dev.sqlite3
test:
  adapter: sqlite3
  database: db/redmine_test.sqlite3
YAML
# The image pins BUNDLE without to development:test. Install the test group.
bundle config unset --local without || true
bundle config unset --global without || true
rm -f .bundle/config
bundle config set --local without development
bundle install
export RAILS_ENV=test
bundle exec rake db:migrate redmine:plugins:migrate
bundle exec rake redmine:plugins:test NAME=redmine_mcp
'
