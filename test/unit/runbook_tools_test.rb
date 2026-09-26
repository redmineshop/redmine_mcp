# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpRunbookToolsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :enabled_modules, :workflows

  def setup
    Setting.rest_api_enabled = '1'
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '1', 'max_results' => '25' }
    @user = User.find(2)
    @server = RedmineMcp::Server.new(user: @user)
    @project = Project.find(1)
    User.current = @user
    enable_template_settings! if RedmineMcp::Tools.templates_plugin?
  end

  def teardown
    User.current = nil
    Setting.plugin_redmine_mcp = RedmineMcp::Settings::DEFAULTS.dup
  end

  def test_missing_templates_plugin_is_a_clear_noop
    with_plugin_flag(:templates_plugin?, false) do
      result = call_tool('list_issue_templates', 'project_id' => 'ecookbook')
      assert_equal false, result['available']
      assert_equal [], result['templates']
      assert_match(/not installed/i, result['message'])

      error = call_tool_raw('get_issue_template', 'id' => 1)
      assert error['isError']
      assert_match(/not installed/i, error['content'].first['text'])
    end
  end

  def test_missing_checklists_plugin_is_a_clear_noop
    with_plugin_flag(:checklists_plugin?, false) do
      result = call_tool('list_issue_checklists', 'issue_id' => Issue.find(1).id)
      assert_equal false, result['available']
      assert_equal [], result['items']
      assert_match(/not installed/i, result['message'])
    end
  end

  def test_write_tools_are_rejected_while_read_only
    issue = Issue.find(1)
    assert_no_difference('Journal.count') do
      error = call_tool_raw('add_issue_note', 'issue_id' => issue.id, 'notes' => 'should not save')
      assert error['isError']
      assert_match(/read-only/i, error['content'].first['text'])
    end

    error = call_tool_raw(
      'set_checklist_item_done',
      'issue_id' => issue.id,
      'position' => 1,
      'is_done' => true
    )
    assert error['isError']
    assert_match(/read-only/i, error['content'].first['text'])

    assert_no_difference('Issue.count') do
      error = call_tool_raw(
        'create_issue_from_template',
        'project_id' => 'ecookbook',
        'template_id' => 1
      )
      assert error['isError']
      assert_match(/read-only/i, error['content'].first['text'])
    end
  end

  def test_add_issue_note_handler_refuses_read_only_directly
    error = assert_raises(RedmineMcp::ToolError) do
      RedmineMcp::Tools.add_issue_note({ 'issue_id' => 1, 'notes' => 'nope' }, @user)
    end
    assert_match(/read-only/i, error.message)
  end

  def test_add_issue_note_when_write_enabled
    enable_writes!
    grant!(:add_issue_notes)
    issue = Issue.find(1)
    original = issue.description.to_s

    result = nil
    assert_difference -> { issue.journals.count }, 1 do
      result = call_tool('add_issue_note', 'issue_id' => issue.id, 'notes' => 'Triage summary')
    end

    issue.reload
    assert_equal issue.id, result['issue_id']
    assert_equal 'Triage summary', result['notes']
    assert_equal original, issue.description.to_s
    assert_equal 'Triage summary', issue.journals.order(:id).last.notes
    assert_not issue.journals.order(:id).last.private_notes?
  end

  def test_add_issue_note_requires_permission
    enable_writes!
    revoke!(:add_issue_notes)
    error = call_tool_raw('add_issue_note', 'issue_id' => Issue.find(1).id, 'notes' => 'nope')
    assert error['isError']
    assert_match(/not allowed to add notes/i, error['content'].first['text'])
  end

  def test_list_and_get_template_respect_permission_and_custom_field_whitelist
    skip 'Issue Templates is not installed' unless RedmineMcp::Tools.templates_plugin?

    grant!(:use_issue_templates)
    @project.enable_module!(:issue_templates)
    template = create_runbook!(
      title: '[Runbook] Triage open issues (read-only)',
      subject: '[Runbook] Triage open issues (read-only)',
      checklist_items: "Confirm whoami and non-admin key\nList or select target project"
    )
    string_field, user_field = create_custom_fields!
    template.update!(
      builtin_fields: {
        string_field.id.to_s => 'keep me',
        user_field.id.to_s => @user.id.to_s
      }
    )

    listed = call_tool('list_issue_templates', 'project_id' => 'ecookbook')
    assert listed['available']
    assert_includes listed['templates'].map { |row| row['id'] }, template.id
    summary = listed['templates'].find { |row| row['id'] == template.id }
    assert_equal '[Runbook] Triage open issues (read-only)', summary['subject']

    fetched = call_tool('get_issue_template', 'id' => template.id)
    assert_equal template.subject, fetched['subject']
    assert_match(/Goal/, fetched['description'])
    assert_includes fetched['checklist_lines'], 'Confirm whoami and non-admin key'
    assert fetched['trackers'].any?
    names = fetched['custom_fields'].map { |field| field['name'] }
    assert_includes names, 'Runbook note'
    assert_not_includes names, 'Runbook owner'
    assert_nil fetched['mail']
    assert_nil fetched['api_key']

    revoke!(:use_issue_templates)
    error = call_tool_raw('get_issue_template', 'id' => template.id)
    assert error['isError']
    assert_match(/not usable/i, error['content'].first['text'])

    denied = call_tool_raw('list_issue_templates', 'project_id' => 'ecookbook')
    assert denied['isError']
    assert_match(/not allowed to use issue templates/i, denied['content'].first['text'])
  end

  def test_list_templates_hides_templates_on_projects_the_user_cannot_use
    skip 'Issue Templates is not installed' unless RedmineMcp::Tools.templates_plugin?

    grant!(:use_issue_templates)
    @project.enable_module!(:issue_templates)
    visible = create_runbook!(
      title: '[Runbook] Standup project summary',
      subject: '[Runbook] Standup project summary'
    )

    other = Project.new(name: 'Hidden runbooks', identifier: 'hidden-runbooks', is_public: false)
    other.trackers = [Tracker.find(1)]
    other.enabled_module_names = %w[issue_tracking issue_templates]
    other.save!
    assert_not other.visible?(@user)
    hidden = create_runbook!(title: '[Runbook] Hidden', subject: '[Runbook] Hidden', project: other)

    ids = call_tool('list_issue_templates')['templates'].map { |row| row['id'] }
    assert_includes ids, visible.id
    assert_not_includes ids, hidden.id

    error = call_tool_raw('get_issue_template', 'id' => hidden.id)
    assert error['isError']
    assert_match(/not usable/i, error['content'].first['text'])
  end

  def test_create_issue_from_template_when_write_enabled
    skip 'Issue Templates is not installed' unless RedmineMcp::Tools.templates_plugin?

    enable_writes!
    grant!(:use_issue_templates)
    grant!(:add_issues)
    @project.enable_module!(:issue_templates)
    grant_checklists! if RedmineMcp::Tools.checklists_plugin?
    template = create_runbook!(
      title: '[Runbook] File a bug from template',
      subject: '[Runbook] File a bug from template',
      content: "**Goal:** File a bug\n",
      checklist_items: "Resolve bug template id\nAdd environment note"
    )

    result = nil
    assert_difference('Issue.count', 1) do
      result = call_tool(
        'create_issue_from_template',
        'project_id' => 'ecookbook',
        'template_id' => template.id,
        'overrides' => { 'subject' => 'Bug: login loop', 'description' => 'Steps' }
      )
    end

    issue = Issue.find(result['id'])
    assert_equal 'Bug: login loop', issue.subject
    assert_equal 'Steps', issue.description
    assert_equal @user.id, issue.author_id
    assert_equal template.id, result['template_id']
    assert_equal "/issues/#{issue.id}", result['path']

    if RedmineMcp::Tools.checklists_plugin? && issue.respond_to?(:issue_checklists)
      assert result.dig('checklist', 'seeded'), result.inspect
      subjects = issue.issue_checklists.order(:position, :id).map(&:subject)
      assert_equal ['Resolve bug template id', 'Add environment note'], subjects
    else
      assert_equal false, result.dig('checklist', 'seeded')
      assert_match(/not installed/i, result.dig('checklist', 'reason').to_s)
    end
  end

  def test_create_issue_from_template_skips_checklist_without_permission
    skip 'Issue Templates is not installed' unless RedmineMcp::Tools.templates_plugin?
    skip 'Issue Checklists is not installed' unless RedmineMcp::Tools.checklists_plugin?

    enable_writes!
    grant!(:use_issue_templates)
    grant!(:add_issues)
    @project.enable_module!(:issue_templates)
    revoke!(:manage_issue_checklists)
    template = create_runbook!(checklist_items: "Resolve bug template id\n")

    result = call_tool(
      'create_issue_from_template',
      'project_id' => @project.id,
      'template_id' => template.id
    )
    issue = Issue.find(result['id'])
    assert_equal false, result.dig('checklist', 'seeded')
    assert_match(/not allowed to manage checklists/i, result.dig('checklist', 'reason').to_s)
    assert_equal 0, issue.issue_checklists.count
  end

  def test_create_issue_from_template_rejects_unknown_override_and_bad_tracker
    skip 'Issue Templates is not installed' unless RedmineMcp::Tools.templates_plugin?

    enable_writes!
    grant!(:use_issue_templates)
    grant!(:add_issues)
    @project.enable_module!(:issue_templates)
    template = create_runbook!(tracker_ids: [1])

    assert_no_difference('Issue.count') do
      error = call_tool_raw(
        'create_issue_from_template',
        'project_id' => 'ecookbook',
        'template_id' => template.id,
        'overrides' => { 'status_id' => 1 }
      )
      assert error['isError']
      assert_match(/unknown override/i, error['content'].first['text'])
    end

    other_tracker = (@project.tracker_ids - [1]).first
    skip 'project has only one tracker' unless other_tracker

    assert_no_difference('Issue.count') do
      error = call_tool_raw(
        'create_issue_from_template',
        'project_id' => 'ecookbook',
        'template_id' => template.id,
        'overrides' => { 'tracker_id' => other_tracker }
      )
      assert error['isError']
      assert_match(/tracker override/i, error['content'].first['text'])
    end
  end

  def test_create_issue_from_template_requires_add_issues
    skip 'Issue Templates is not installed' unless RedmineMcp::Tools.templates_plugin?

    enable_writes!
    grant!(:use_issue_templates)
    @project.enable_module!(:issue_templates)
    revoke!(:add_issues)
    template = create_runbook!

    assert_no_difference('Issue.count') do
      error = call_tool_raw(
        'create_issue_from_template',
        'project_id' => 'ecookbook',
        'template_id' => template.id
      )
      assert error['isError']
      assert_match(/not allowed to add issues/i, error['content'].first['text'])
    end
  end

  def test_set_checklist_item_done_by_id_and_position
    skip 'Issue Checklists is not installed' unless RedmineMcp::Tools.checklists_plugin?

    enable_writes!
    grant_checklists!
    issue = Issue.find(1)
    issue.issue_checklists.delete_all
    first = issue.issue_checklists.create!(subject: 'Confirm whoami and non-admin key', is_done: false)
    second = issue.issue_checklists.create!(subject: 'List or select target project', is_done: false)

    by_id = call_tool(
      'set_checklist_item_done',
      'issue_id' => issue.id,
      'item_id' => first.id,
      'is_done' => true
    )
    assert_equal true, by_id['is_done']
    assert first.reload.is_done?

    by_position = call_tool(
      'set_checklist_item_done',
      'issue_id' => issue.id,
      'position' => second.position,
      'is_done' => true
    )
    assert_equal true, by_position['is_done']
    assert second.reload.is_done?

    listed = call_tool('list_issue_checklists', 'issue_id' => issue.id)
    assert listed['available']
    assert_equal [true, true], listed['items'].map { |item| item['is_done'] }
  end

  def test_set_checklist_item_done_requires_manage_permission
    skip 'Issue Checklists is not installed' unless RedmineMcp::Tools.checklists_plugin?

    enable_writes!
    issue = Issue.find(1)
    issue.issue_checklists.delete_all
    item = issue.issue_checklists.create!(subject: 'Confirm whoami and non-admin key', is_done: false)
    revoke!(:manage_issue_checklists)

    error = call_tool_raw(
      'set_checklist_item_done',
      'issue_id' => issue.id,
      'item_id' => item.id,
      'is_done' => true
    )
    assert error['isError']
    assert_match(/not allowed to manage checklists/i, error['content'].first['text'])
    assert_not item.reload.is_done?
  end

  private

  def enable_writes!
    Setting.plugin_redmine_mcp = { 'enabled' => '1', 'read_only' => '0', 'max_results' => '25' }
  end

  def enable_template_settings!
    Setting.plugin_redmine_issue_templates = {
      'confirm_overwrite_on_tracker_change' => '1',
      'apply_global_templates' => '1'
    }
  end

  def grant!(permission)
    return unless Redmine::AccessControl.permission(permission)

    Role.find(1).add_permission!(permission)
    reload_actor!
  end

  def revoke!(permission)
    role = Role.find(1)
    role.remove_permission!(permission) if role.has_permission?(permission)
    reload_actor!
  end

  def reload_actor!
    @user = User.find(2)
    User.current = @user
    @server = RedmineMcp::Server.new(user: @user)
  end

  def grant_checklists!
    grant!(:manage_issue_checklists)
  end

  def create_runbook!(attributes = {})
    tracker_ids = attributes.delete(:tracker_ids) || [1]
    RedmineIssueTemplates::TemplateFactory.create!(
      {
        project: @project,
        author: @user,
        title: '[Runbook] File a bug from template',
        subject: '[Runbook] File a bug from template',
        content: "**Goal:** File a bug\n\n**Done when:** Issue exists.\n",
        enabled: true
      }.merge(attributes).merge(tracker_ids: tracker_ids)
    )
  end

  def create_custom_fields!
    string_field = IssueCustomField.create!(
      name: 'Runbook note',
      field_format: 'string',
      is_for_all: true
    )
    user_field = IssueCustomField.create!(
      name: 'Runbook owner',
      field_format: 'user',
      is_for_all: true
    )
    [string_field, user_field]
  end

  def with_plugin_flag(name, value)
    RedmineMcp::Tools.define_singleton_method(name) { value }
    yield
  ensure
    singleton = RedmineMcp::Tools.singleton_class
    singleton.remove_method(name) if singleton.instance_methods(false).include?(name)
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
end
