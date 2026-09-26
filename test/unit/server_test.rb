# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpServerTest < ActiveSupport::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles, :issues,
           :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :enabled_modules, :wikis, :wiki_pages, :wiki_contents

  def setup
    Setting.rest_api_enabled = '1'
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '1', 'max_results' => '2' }
    @user = User.find(2)
    @server = RedmineMcp::Server.new(user: @user)
    User.current = @user
  end

  def teardown
    User.current = nil
    Setting.plugin_redmine_mcp = RedmineMcp::Settings::DEFAULTS.dup
  end

  def test_initialize_negotiates_protocol
    response = @server.handle(
      'jsonrpc' => '2.0',
      'id' => 1,
      'method' => 'initialize',
      'params' => { 'protocolVersion' => '2025-03-26', 'capabilities' => {}, 'clientInfo' => { 'name' => 'test' } }
    )
    assert_equal '2025-03-26', response['result']['protocolVersion']
    assert_equal 'redmine-mcp', response['result']['serverInfo']['name']
  end

  def test_notification_returns_nil
    assert_nil @server.handle('jsonrpc' => '2.0', 'method' => 'notifications/initialized', 'params' => {})
  end

  def test_unknown_method
    response = @server.handle('jsonrpc' => '2.0', 'id' => 2, 'method' => 'boom')
    assert_equal(-32601, response['error']['code'])
  end

  def test_tools_list_hides_write_when_read_only
    names = tool_names_from(@server.handle('jsonrpc' => '2.0', 'id' => 3, 'method' => 'tools/list'))
    assert_includes names, 'whoami'
    assert_includes names, 'list_issue_templates'
    assert_not_includes names, 'update_wiki_page'
    assert_not_includes names, 'add_issue_note'
    assert_not_includes names, 'set_checklist_item_done'
    assert_not_includes names, 'create_issue_from_template'
  end

  def test_whoami_omits_email_and_api_key
    result = call_tool('whoami')
    assert_equal @user.login, result['login']
    assert_nil result['mail']
    assert_nil result['api_key']
    assert_nil result['hashed_password']
  end

  def test_search_issues_respects_result_cap
    result = call_tool('search_issues', 'project' => 'ecookbook')
    assert_operator result.length, :<=, 2
  end

  def test_get_issue_returns_structure_and_body
    issue = Issue.find(1)
    result = call_tool('get_issue', 'id' => issue.id)
    assert_equal issue.id, result['id']
    assert_equal issue.subject, result['subject']
    assert result.key?('description')
    assert result.key?('status')
    assert result.key?('tracker')
    assert_nil result.dig('author', 'mail')
  end

  def test_hidden_project_is_not_returned
    error = call_tool_raw('get_project', 'id' => 'does-not-exist')
    assert error['isError']
    assert_match(/not visible|not found/i, error['content'].first['text'])
  end

  def test_update_wiki_page_rejected_in_read_only
    error = call_tool_raw('update_wiki_page', 'project' => 'ecookbook', 'title' => 'Agent notes', 'text' => 'nope')
    assert error['isError']
    assert_match(/read-only/i, error['content'].first['text'])
  end

  def test_update_wiki_page_creates_page_when_write_enabled
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '0', 'max_results' => '25' }
    Role.find(1).add_permission!(:edit_wiki_pages) unless Role.find(1).has_permission?(:edit_wiki_pages)
    ensure_wiki(Project.find(1))

    result = call_tool(
      'update_wiki_page',
      'project' => 'ecookbook',
      'title' => 'Agent notes',
      'text' => "* Repeated FAQ: GitHub clone vs email download\n"
    )
    assert result['updated']
    page = Project.find(1).wiki.find_page('Agent notes')
    assert page
    assert_match(/Repeated FAQ/, page.content.text)
  end

  def test_stale_wiki_version_is_rejected
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '0', 'max_results' => '25' }
    Role.find(1).add_permission!(:edit_wiki_pages) unless Role.find(1).has_permission?(:edit_wiki_pages)
    wiki = ensure_wiki(Project.find(1))
    page = wiki.find_or_new_page('Versioned notes')
    content = page.content || WikiContent.new(page: page)
    content.text = 'v1'
    content.author = @user
    page.save_with_content(content)
    page.reload

    error = call_tool_raw(
      'update_wiki_page',
      'project' => 'ecookbook',
      'title' => 'Versioned notes',
      'text' => 'v2',
      'version' => page.content.version - 1
    )
    assert error['isError']
    assert_match(/version conflict/i, error['content'].first['text'])
  end

  private

  def tool_names_from(response)
    response['result']['tools'].map { |tool| tool['name'] }
  end

  def call_tool(name, arguments = {})
    payload = call_tool_raw(name, arguments)
    refute payload['isError'], payload.inspect
    JSON.parse(payload['content'].first['text'])
  end

  def call_tool_raw(name, arguments = {})
    response = @server.handle(
      'jsonrpc' => '2.0',
      'id' => 10,
      'method' => 'tools/call',
      'params' => { 'name' => name, 'arguments' => arguments }
    )
    response['result']
  end

  def ensure_wiki(project)
    names = (project.enabled_module_names + ['wiki']).uniq
    project.enabled_module_names = names
    project.save!
    project.reload
    project.wiki || Wiki.create!(project: project, start_page: 'Wiki')
  end
end
