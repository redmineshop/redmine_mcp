# frozen_string_literal: true

module RedmineMcp
  module Tools
    module_function

    def whoami(_args, user)
      {
        'id' => user.id,
        'login' => user.login,
        'firstname' => user.firstname,
        'lastname' => user.lastname,
        'admin' => user.admin?,
        'language' => user.language
      }
    end

    def list_projects(args, user)
      scope = Project.visible(user).sorted
      query = args['query'].to_s.strip
      if query.present?
        pattern = like_pattern(query)
        scope = scope.where(
          'projects.name LIKE ? OR projects.identifier LIKE ?',
          pattern, pattern
        )
      end
      cap(scope).map { |project| project_summary(project) }
    end

    def get_project(args, user)
      project = find_visible_project!(args['id'], user)
      project_summary(project).merge(
        'description' => project.description.to_s,
        'is_public' => project.is_public?,
        'status' => project.status,
        'modules' => project.enabled_module_names.sort,
        'trackers' => project.trackers.sorted.map { |tracker| { 'id' => tracker.id, 'name' => tracker.name } }
      )
    end

    def search_issues(args, user)
      scope = Issue.visible(user).includes(:project, :tracker, :status, :priority, :author)
      if args['project'].present?
        project = find_visible_project!(args['project'], user)
        scope = scope.where(project_id: project.id)
      end
      scope = scope.where(status_id: args['status_id']) if args['status_id'].present?
      scope = scope.where(tracker_id: args['tracker_id']) if args['tracker_id'].present?
      query = args['query'].to_s.strip
      if query.present?
        pattern = like_pattern(query)
        scope = scope.where(
          'issues.subject LIKE ? OR issues.description LIKE ?',
          pattern, pattern
        )
      end
      limit = requested_limit(args)
      cap(scope.order(updated_on: :desc), limit).map { |issue| issue_summary(issue) }
    end

    def get_issue(args, user)
      issue = Issue.visible(user).find_by(id: args['id'])
      raise ToolError, 'Issue not found or not visible' unless issue

      {
        'id' => issue.id,
        'subject' => issue.subject,
        'description' => issue.description.to_s,
        'project' => { 'id' => issue.project_id, 'identifier' => issue.project.identifier, 'name' => issue.project.name },
        'tracker' => { 'id' => issue.tracker_id, 'name' => issue.tracker.name },
        'status' => { 'id' => issue.status_id, 'name' => issue.status.name, 'is_closed' => issue.status.is_closed? },
        'priority' => { 'id' => issue.priority_id, 'name' => issue.priority.name },
        'author' => person(issue.author),
        'assigned_to' => person(issue.assigned_to),
        'start_date' => issue.start_date,
        'due_date' => issue.due_date,
        'done_ratio' => issue.done_ratio,
        'updated_on' => issue.updated_on,
        'custom_fields' => visible_custom_field_values(issue, user),
        'notes' => visible_notes(issue, user)
      }
    end

    def list_enumerations(_args, _user)
      {
        'trackers' => Tracker.sorted.map { |item| { 'id' => item.id, 'name' => item.name } },
        'issue_statuses' => IssueStatus.sorted.map { |item| { 'id' => item.id, 'name' => item.name, 'is_closed' => item.is_closed? } },
        'priorities' => IssuePriority.active.sorted.map { |item| { 'id' => item.id, 'name' => item.name } },
        'activities' => TimeEntryActivity.active.sorted.map { |item| { 'id' => item.id, 'name' => item.name } }
      }
    end

    def list_custom_fields(_args, user)
      fields = IssueCustomField.sorted.select { |field| custom_field_visible?(field, user) }
      fields.map do |field|
        {
          'id' => field.id,
          'name' => field.name,
          'field_format' => field.field_format,
          'is_required' => field.is_required?,
          'is_for_all' => field.is_for_all?
        }
      end
    end

    def list_users(args, user)
      scope = visible_users(user)
      query = args['query'].to_s.strip
      if query.present?
        pattern = like_pattern(query)
        scope = scope.where(
          'users.login LIKE ? OR users.firstname LIKE ? OR users.lastname LIKE ?',
          pattern, pattern, pattern
        )
      end
      cap(scope).map { |member| person(member) }
    end

    def list_wiki_pages(args, user)
      project = find_visible_project!(args['project'], user)
      wiki = visible_wiki!(project, user)
      cap(wiki.pages.order(:title)).map { |page| wiki_page_summary(page) }
    end

    def get_wiki_page(args, user)
      project = find_visible_project!(args['project'], user)
      wiki = visible_wiki!(project, user)
      page = wiki.find_page(args['title'].to_s)
      raise ToolError, 'Wiki page not found' unless page

      wiki_page_summary(page).merge(
        'text' => page.content&.text.to_s,
        'comments' => page.content&.comments.to_s
      )
    end

    def update_wiki_page(args, user)
      raise ToolError, 'Plugin is in read-only mode' if Settings.read_only?

      project = find_visible_project!(args['project'], user)
      wiki = visible_wiki!(project, user)
      unless user.allowed_to?(:edit_wiki_pages, project)
        raise ToolError, 'Not allowed to edit wiki pages on this project'
      end

      title = args['title'].to_s
      raise ToolError, 'Wiki page title is required' if title.blank?

      page = wiki.find_or_new_page(title)
      content = page.content || WikiContent.new(page: page)
      if args['version'] && content.persisted? && content.version != args['version'].to_i
        raise ToolError, "Wiki page version conflict (current #{content.version})"
      end

      content.text = args['text'].to_s
      content.author = user
      content.comments = args['comments'].to_s.presence || 'Updated via Redmine MCP'
      saved = if page.respond_to?(:save_with_content)
                page.save_with_content(content)
              else
                page.content = content
                page.save && content.save
              end
      unless saved
        messages = (page.errors.full_messages + content.errors.full_messages).uniq
        raise ToolError, messages.join(', ').presence || 'Wiki page could not be saved'
      end

      page.reload
      wiki_page_summary(page).merge('text' => page.content&.text.to_s, 'updated' => true)
    end

    def find_visible_project!(id_or_identifier, user)
      token = id_or_identifier.to_s.strip
      raise ToolError, 'Project is required' if token.blank?

      scope = Project.visible(user)
      project = if token.match?(/\A\d+\z/)
                  scope.find_by(id: token.to_i) || scope.find_by(identifier: token)
                else
                  scope.find_by(identifier: token)
                end
      raise ToolError, 'Project not found or not visible' unless project

      project
    end

    def visible_wiki!(project, user)
      unless user.allowed_to?(:view_wiki_pages, project)
        raise ToolError, 'Not allowed to view wiki pages on this project'
      end

      wiki = project.wiki
      raise ToolError, 'Wiki module is not enabled on this project' unless wiki

      wiki
    end

    def project_summary(project)
      {
        'id' => project.id,
        'identifier' => project.identifier,
        'name' => project.name
      }
    end

    def issue_summary(issue)
      {
        'id' => issue.id,
        'subject' => issue.subject,
        'project' => { 'id' => issue.project_id, 'identifier' => issue.project.identifier, 'name' => issue.project.name },
        'tracker' => issue.tracker.name,
        'status' => issue.status.name,
        'priority' => issue.priority.name,
        'updated_on' => issue.updated_on
      }
    end

    def wiki_page_summary(page)
      {
        'title' => page.title,
        'parent' => page.parent&.title,
        'version' => page.content&.version,
        'updated_on' => page.content&.updated_on,
        'author' => person(page.content&.author)
      }
    end

    def person(user)
      return nil unless user

      {
        'id' => user.id,
        'login' => user.respond_to?(:login) ? user.login : nil,
        'name' => user.name
      }
    end

    def visible_custom_field_values(issue, user)
      values =
        if issue.respond_to?(:visible_custom_field_values)
          issue.visible_custom_field_values(user)
        else
          issue.custom_field_values.select { |value| custom_field_visible?(value.custom_field, user) }
        end
      values.map { |value| { 'name' => value.custom_field.name, 'value' => value.value } }
    end

    def custom_field_visible?(field, user)
      return true unless field.respond_to?(:visible?)

      if field.method(:visible?).arity == 0
        field.visible?
      else
        field.visible?(user)
      end
    end

    def visible_notes(issue, user)
      journals = issue.journals.includes(:user).order(:id)
      journals = journals.reject { |journal| journal.notes.blank? }
      unless user.allowed_to?(:view_private_notes, issue.project)
        journals = journals.reject(&:private_notes?)
      end
      journals.last(20).map do |journal|
        {
          'id' => journal.id,
          'user' => person(journal.user),
          'notes' => journal.notes,
          'created_on' => journal.created_on,
          'private_notes' => journal.private_notes?
        }
      end
    end

    def visible_users(user)
      scope =
        if User.respond_to?(:visible)
          User.visible(user)
        else
          Principal.visible(user).where(type: 'User')
        end
      scope = scope.active if scope.respond_to?(:active)
      scope.sorted
    end

    def like_pattern(query)
      escaped = query.to_s.gsub(/[%_\\]/) { |char| "\\#{char}" }
      "%#{escaped}%"
    end

    def requested_limit(args)
      requested = args['limit'].to_i
      requested.positive? ? [requested, Settings.max_results].min : Settings.max_results
    end

    def cap(scope, limit = Settings.max_results)
      scope.limit(limit)
    end
  end
end
