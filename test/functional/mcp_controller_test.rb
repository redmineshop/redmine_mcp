# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class McpControllerTest < Redmine::ControllerTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :enabled_modules, :wikis, :wiki_pages, :wiki_contents

  def setup
    Setting.rest_api_enabled = '1'
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '1', 'max_results' => '25' }
    @user = User.find(2)
    @api_key = @user.api_key
    @request.session[:user_id] = nil
    User.current = nil
  end

  def teardown
    Setting.plugin_redmine_mcp = RedmineMcp::Settings::DEFAULTS.dup
    User.current = nil
  end

  def test_get_is_method_not_allowed
    get :handle
    assert_response :method_not_allowed
  end

  def test_disabled_endpoint_is_forbidden
    Setting.plugin_redmine_mcp = { 'enabled' => '0', 'read_only' => '1', 'max_results' => '25' }
    mcp_post('initialize', {}, id: 1)
    assert_response :forbidden
    assert_equal(-32001, json_body['error']['code'])
  end

  def test_missing_api_key_is_unauthorized
    @request.headers['CONTENT_TYPE'] = 'application/json'
    post :handle, body: { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }.to_json
    assert_response :unauthorized
  end

  def test_invalid_api_key_is_unauthorized
    @request.headers['X-Redmine-API-Key'] = 'not-a-real-key'
    mcp_post('initialize', {}, id: 1)
    assert_response :unauthorized
  end

  def test_rest_api_disabled_is_forbidden
    Setting.rest_api_enabled = '0'
    @request.headers['X-Redmine-API-Key'] = @api_key
    mcp_post('initialize', {}, id: 1)
    assert_response :forbidden
    assert_match(/REST API/i, json_body['error']['message'])
  end

  def test_initialize_and_tools_list_with_api_key
    @request.headers['X-Redmine-API-Key'] = @api_key
    mcp_post('initialize', { 'protocolVersion' => '2024-11-05', 'capabilities' => {}, 'clientInfo' => { 'name' => 'minitest' } }, id: 1)
    assert_response :success
    assert_equal 'redmine-mcp', json_body['result']['serverInfo']['name']

    mcp_post('tools/list', {}, id: 2)
    assert_response :success
    names = json_body['result']['tools'].map { |tool| tool['name'] }
    assert_includes names, 'search_issues'
    assert_includes names, 'get_issue'
    assert_not_includes names, 'update_wiki_page'
  end

  def test_bearer_token_auth
    @request.headers['Authorization'] = "Bearer #{@api_key}"
    mcp_post('tools/call', { 'name' => 'whoami', 'arguments' => {} }, id: 3)
    assert_response :success
    payload = JSON.parse(json_body['result']['content'].first['text'])
    assert_equal @user.login, payload['login']
    assert_nil payload['mail']
  end

  def test_search_issues_and_get_issue
    @request.headers['X-Redmine-API-Key'] = @api_key
    mcp_post('tools/call', { 'name' => 'search_issues', 'arguments' => { 'project' => 'ecookbook' } }, id: 4)
    assert_response :success
    issues = JSON.parse(json_body['result']['content'].first['text'])
    assert issues.is_a?(Array)
    refute_empty issues

    issue_id = issues.first['id']
    mcp_post('tools/call', { 'name' => 'get_issue', 'arguments' => { 'id' => issue_id } }, id: 5)
    assert_response :success
    issue = JSON.parse(json_body['result']['content'].first['text'])
    assert_equal issue_id, issue['id']
    assert issue['subject'].present?
  end

  def test_list_wiki_pages
    @request.headers['X-Redmine-API-Key'] = @api_key
    mcp_post('tools/call', { 'name' => 'list_wiki_pages', 'arguments' => { 'project' => 'ecookbook' } }, id: 6)
    assert_response :success
    refute json_body['result']['isError']
    pages = JSON.parse(json_body['result']['content'].first['text'])
    assert pages.is_a?(Array)
  end

  def test_permission_denied_for_invisible_project
    @request.headers['X-Redmine-API-Key'] = User.find(3).api_key
    mcp_post('tools/call', { 'name' => 'get_project', 'arguments' => { 'id' => 'onlinestore' } }, id: 7)
    assert_response :success
    assert json_body['result']['isError']
  end

  def test_batch_requests_rejected
    @request.headers['X-Redmine-API-Key'] = @api_key
    @request.headers['CONTENT_TYPE'] = 'application/json'
    post :handle, body: [{ jsonrpc: '2.0', id: 1, method: 'ping' }].to_json
    assert_response :bad_request
    assert_match(/Batch/i, json_body['error']['message'])
  end

  def test_result_cap_on_http
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '1', 'max_results' => '1' }
    @request.headers['X-Redmine-API-Key'] = @api_key
    mcp_post('tools/call', { 'name' => 'search_issues', 'arguments' => { 'project' => 'ecookbook' } }, id: 8)
    assert_response :success
    issues = JSON.parse(json_body['result']['content'].first['text'])
    assert_equal 1, issues.length
  end

  def test_wiki_update_when_read_only_off
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '0', 'max_results' => '25' }
    Role.find(1).add_permission!(:edit_wiki_pages) unless Role.find(1).has_permission?(:edit_wiki_pages)
    @request.headers['X-Redmine-API-Key'] = @api_key
    mcp_post(
      'tools/list',
      {},
      id: 9
    )
    names = json_body['result']['tools'].map { |tool| tool['name'] }
    assert_includes names, 'update_wiki_page'

    mcp_post(
      'tools/call',
      {
        'name' => 'update_wiki_page',
        'arguments' => {
          'project' => 'ecookbook',
          'title' => 'Agent notes',
          'text' => '* Community GitHub vs email download'
        }
      },
      id: 10
    )
    assert_response :success
    refute json_body['result']['isError'], json_body.inspect
    page = Project.find(1).wiki.find_page('Agent notes')
    assert page
    assert_match(/GitHub/, page.content.text)
  end

  def test_parse_error
    @request.headers['X-Redmine-API-Key'] = @api_key
    @request.headers['CONTENT_TYPE'] = 'application/json'
    post :handle, body: '{not-json'
    assert_response :bad_request
    assert_equal(-32700, json_body['error']['code'])
  end

  private

  def mcp_post(method, params, id:)
    @request.headers['CONTENT_TYPE'] = 'application/json'
    payload = { 'jsonrpc' => '2.0', 'id' => id, 'method' => method, 'params' => params }
    post :handle, body: payload.to_json
  end

  def json_body
    JSON.parse(@response.body)
  end
end
