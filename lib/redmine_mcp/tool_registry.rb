# frozen_string_literal: true

module RedmineMcp
  class ToolRegistry
    Tool = Struct.new(:name, :description, :input_schema, :write, :handler, keyword_init: true)

    class << self
      def all
        @all ||= build
      end

      def visible(read_only:)
        read_only ? all.reject(&:write) : all
      end

      def find(name, read_only:)
        visible(read_only: read_only).find { |tool| tool.name == name.to_s }
      end

      def reset!
        @all = nil
      end

      private

      def object_schema(properties = {}, required = [])
        schema = {
          'type' => 'object',
          'properties' => properties,
          'additionalProperties' => false
        }
        schema['required'] = required if required.any?
        schema
      end

      def build
        [
          Tool.new(
            name: 'whoami',
            description: 'Return the Redmine user that owns the API key (no email, no API key).',
            input_schema: object_schema,
            write: false,
            handler: :whoami
          ),
          Tool.new(
            name: 'list_projects',
            description: 'List projects visible to the current user.',
            input_schema: object_schema(
              'query' => { 'type' => 'string', 'description' => 'Optional name or identifier filter' }
            ),
            write: false,
            handler: :list_projects
          ),
          Tool.new(
            name: 'get_project',
            description: 'Get one visible project by id or identifier, including modules and trackers.',
            input_schema: object_schema(
              { 'id' => { 'type' => 'string', 'description' => 'Project id or identifier' } },
              ['id']
            ),
            write: false,
            handler: :get_project
          ),
          Tool.new(
            name: 'search_issues',
            description: 'Search visible issues by text, project, status, or tracker. Read only.',
            input_schema: object_schema(
              'query' => { 'type' => 'string', 'description' => 'Match subject or description' },
              'project' => { 'type' => 'string', 'description' => 'Project id or identifier' },
              'status_id' => { 'type' => 'integer' },
              'tracker_id' => { 'type' => 'integer' },
              'limit' => { 'type' => 'integer', 'description' => 'Capped by plugin max-results setting' }
            ),
            write: false,
            handler: :search_issues
          ),
          Tool.new(
            name: 'get_issue',
            description: 'Get one visible issue: structure, description, visible custom fields, and notes. Read only.',
            input_schema: object_schema(
              { 'id' => { 'type' => 'integer', 'description' => 'Issue id' } },
              ['id']
            ),
            write: false,
            handler: :get_issue
          ),
          Tool.new(
            name: 'list_issue_templates',
            description: 'List Issue Templates the current user can use. Optional project_id limits the list to that project (including global templates when the project applies them). Returns available: false when Issue Templates is not installed.',
            input_schema: object_schema(
              'project_id' => { 'type' => 'string', 'description' => 'Optional project id or identifier' }
            ),
            write: false,
            handler: :list_issue_templates
          ),
          Tool.new(
            name: 'get_issue_template',
            description: 'Get one Issue Template the current user can use: subject, description, trackers, checklist lines, and whitelisted custom fields only.',
            input_schema: object_schema(
              { 'id' => { 'type' => 'integer', 'description' => 'Issue template id' } },
              ['id']
            ),
            write: false,
            handler: :get_issue_template
          ),
          Tool.new(
            name: 'list_issue_checklists',
            description: 'List checklist items on a visible issue. Returns available: false when Issue Checklists is not installed.',
            input_schema: object_schema(
              { 'issue_id' => { 'type' => 'integer', 'description' => 'Issue id' } },
              ['issue_id']
            ),
            write: false,
            handler: :list_issue_checklists
          ),
          Tool.new(
            name: 'list_enumerations',
            description: 'List trackers, issue statuses, priorities, and time-entry activities.',
            input_schema: object_schema,
            write: false,
            handler: :list_enumerations
          ),
          Tool.new(
            name: 'list_custom_fields',
            description: 'List issue custom fields visible to the current user.',
            input_schema: object_schema,
            write: false,
            handler: :list_custom_fields
          ),
          Tool.new(
            name: 'list_users',
            description: 'List users visible to the current user (no email addresses).',
            input_schema: object_schema(
              'query' => { 'type' => 'string', 'description' => 'Optional login or name filter' }
            ),
            write: false,
            handler: :list_users
          ),
          Tool.new(
            name: 'list_wiki_pages',
            description: 'List wiki pages in a visible project.',
            input_schema: object_schema(
              { 'project' => { 'type' => 'string', 'description' => 'Project id or identifier' } },
              ['project']
            ),
            write: false,
            handler: :list_wiki_pages
          ),
          Tool.new(
            name: 'get_wiki_page',
            description: 'Read one wiki page (title, text, version) in a visible project.',
            input_schema: object_schema(
              {
                'project' => { 'type' => 'string', 'description' => 'Project id or identifier' },
                'title' => { 'type' => 'string', 'description' => 'Wiki page title' }
              },
              %w[project title]
            ),
            write: false,
            handler: :get_wiki_page
          ),
          Tool.new(
            name: 'update_wiki_page',
            description: 'Create or update wiki page text. Hidden while the plugin is in read-only mode.',
            input_schema: object_schema(
              {
                'project' => { 'type' => 'string', 'description' => 'Project id or identifier' },
                'title' => { 'type' => 'string', 'description' => 'Wiki page title' },
                'text' => { 'type' => 'string', 'description' => 'Full page text (Textile or Markdown as the project uses)' },
                'comments' => { 'type' => 'string', 'description' => 'Optional change comment' },
                'version' => { 'type' => 'integer', 'description' => 'Current version; reject if stale' }
              },
              %w[project title text]
            ),
            write: true,
            handler: :update_wiki_page
          ),
          Tool.new(
            name: 'add_issue_note',
            description: 'Add a note to a visible issue. Hidden while the plugin is in read-only mode. Does not change the issue description or status.',
            input_schema: object_schema(
              {
                'issue_id' => { 'type' => 'integer', 'description' => 'Issue id' },
                'notes' => { 'type' => 'string', 'description' => 'Note text. Maximum 10000 characters.' }
              },
              %w[issue_id notes]
            ),
            write: true,
            handler: :add_issue_note
          ),
          Tool.new(
            name: 'set_checklist_item_done',
            description: 'Set a checklist item done or not done. Requires manage checklists on the issue project. Pass item_id or position. Hidden while the plugin is in read-only mode.',
            input_schema: object_schema(
              {
                'issue_id' => { 'type' => 'integer', 'description' => 'Issue id' },
                'item_id' => { 'type' => 'integer', 'description' => 'Checklist item id. Used when present.' },
                'position' => { 'type' => 'integer', 'description' => '1-based position when item_id is omitted' },
                'is_done' => { 'type' => 'boolean', 'description' => 'true to check, false to uncheck' }
              },
              %w[issue_id is_done]
            ),
            write: true,
            handler: :set_checklist_item_done
          ),
          Tool.new(
            name: 'create_issue_from_template',
            description: 'Create an issue from an Issue Template the user can use on the project. Optional overrides: subject, description, tracker_id. Hidden while the plugin is in read-only mode.',
            input_schema: object_schema(
              {
                'project_id' => { 'type' => 'string', 'description' => 'Project id or identifier' },
                'template_id' => { 'type' => 'integer', 'description' => 'Issue template id' },
                'overrides' => {
                  'type' => 'object',
                  'description' => 'Optional subject, description, or tracker_id',
                  'properties' => {
                    'subject' => { 'type' => 'string' },
                    'description' => { 'type' => 'string' },
                    'tracker_id' => { 'type' => 'integer' }
                  },
                  'additionalProperties' => false
                }
              },
              %w[project_id template_id]
            ),
            write: true,
            handler: :create_issue_from_template
          )
        ]
      end
    end
  end
end
