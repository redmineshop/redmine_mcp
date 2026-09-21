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
          )
        ]
      end
    end
  end
end
