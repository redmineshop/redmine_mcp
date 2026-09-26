# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpToolRegistryTest < ActiveSupport::TestCase
  def test_read_only_hides_write_tools
    names = RedmineMcp::ToolRegistry.visible(read_only: true).map(&:name)
    assert_includes names, 'search_issues'
    assert_includes names, 'get_issue'
    assert_includes names, 'list_wiki_pages'
    assert_includes names, 'get_wiki_page'
    assert_not_includes names, 'update_wiki_page'
    assert_not_includes names, 'create_issue'
    assert_not_includes names, 'update_issue'
    assert_not_includes names, 'add_issue_note'
    assert_not_includes names, 'set_checklist_item_done'
    assert_not_includes names, 'create_issue_from_template'
    assert_includes names, 'list_issue_templates'
    assert_includes names, 'get_issue_template'
    assert_includes names, 'list_issue_checklists'
  end

  def test_write_mode_includes_gated_write_tools
    names = RedmineMcp::ToolRegistry.visible(read_only: false).map(&:name)
    assert_includes names, 'update_wiki_page'
    assert_includes names, 'add_issue_note'
    assert_includes names, 'set_checklist_item_done'
    assert_includes names, 'create_issue_from_template'
    assert_equal %w[
      add_issue_note
      create_issue_from_template
      set_checklist_item_done
      update_wiki_page
    ], RedmineMcp::ToolRegistry.all.select(&:write).map(&:name).sort
  end

  def test_find_returns_nil_for_hidden_write_tool
    assert_nil RedmineMcp::ToolRegistry.find('update_wiki_page', read_only: true)
    assert RedmineMcp::ToolRegistry.find('update_wiki_page', read_only: false)
  end

  def test_no_shop_cms_tools
    names = RedmineMcp::ToolRegistry.all.map(&:name)
    assert_empty names.grep(/catalog|shop|price|frontpage|markdown/)
  end
end
