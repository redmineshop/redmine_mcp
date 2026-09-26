# frozen_string_literal: true

module RedmineMcp
  # Issue Templates and Issue Checklists tools. Included on Tools.
  # Read tools no-op with a clear message when the other plugin is absent.
  # Write tools stay hidden while read-only mode is on; these methods reject
  # a direct call the same way.
  module RunbookTools
    NOTE_MAX_LENGTH = 10_000

    def templates_plugin?
      return false unless Redmine::Plugin.installed?(:redmine_issue_templates)

      CommunityIssueTemplate
      RedmineIssueTemplates::ApplyPayload
      true
    rescue NameError
      false
    end

    def checklists_plugin?
      return false unless Redmine::Plugin.installed?(:redmine_issue_checklists)

      IssueChecklist
      true
    rescue NameError
      false
    end

    def list_issue_templates(args, user)
      unless templates_plugin?
        return {
          'available' => false,
          'templates' => [],
          'message' => 'Issue Templates is not installed'
        }
      end

      scope = if args['project_id'].present?
                project = RedmineMcp::Tools.find_visible_project!(args['project_id'], user)
                require_template_access!(user, project)
                CommunityIssueTemplate.visible_for(project).order(:position, :id)
              else
                templates_scope_for(user)
              end

      {
        'available' => true,
        'templates' => RedmineMcp::Tools.cap(scope).map { |template| template_summary(template) }
      }
    end

    def get_issue_template(args, user)
      raise ToolError, 'Issue Templates is not installed' unless templates_plugin?
      raise ToolError, 'Issue template id is required' if args['id'].blank?

      template = CommunityIssueTemplate.enabled.find_by(id: args['id'])
      unless template && template_visible_to?(template, user)
        raise ToolError, 'Issue template not found or not usable'
      end

      {
        'id' => template.id,
        'title' => template.title,
        'subject' => template.subject.to_s,
        'description' => template.content.to_s,
        'project_id' => template.project_id,
        'global' => template.project_id.nil?,
        'trackers' => tracker_payload(template),
        'checklist_lines' => checklist_lines(template),
        'custom_fields' => whitelisted_custom_fields(template, user)
      }
    end

    def list_issue_checklists(args, user)
      issue = visible_issue!(args['issue_id'], user)
      unless checklists_plugin? && issue.respond_to?(:issue_checklists)
        return {
          'available' => false,
          'issue_id' => issue.id,
          'items' => [],
          'message' => 'Issue Checklists is not installed'
        }
      end

      items = issue.issue_checklists.respond_to?(:sorted) ? issue.issue_checklists.sorted : issue.issue_checklists.order(:position, :id)
      {
        'available' => true,
        'issue_id' => issue.id,
        'items' => items.map { |item| checklist_payload(item) }
      }
    end

    def add_issue_note(args, user)
      raise ToolError, 'Plugin is in read-only mode' if Settings.read_only?

      issue = visible_issue!(args['issue_id'], user)
      unless notes_allowed?(user, issue)
        raise ToolError, 'Not allowed to add notes on this issue'
      end

      notes = args['notes'].to_s.strip
      raise ToolError, 'Notes are required' if notes.blank?
      raise ToolError, "Notes are limited to #{NOTE_MAX_LENGTH} characters" if notes.length > NOTE_MAX_LENGTH

      with_user(user) do
        issue.init_journal(user, notes)
        unless issue.save
          raise ToolError, issue.errors.full_messages.join(', ').presence || 'Note could not be saved'
        end
      end

      journal = issue.journals.order(:id).last
      {
        'issue_id' => issue.id,
        'journal_id' => journal&.id,
        'notes' => journal&.notes.to_s
      }
    end

    def set_checklist_item_done(args, user)
      raise ToolError, 'Plugin is in read-only mode' if Settings.read_only?

      issue = visible_issue!(args['issue_id'], user)
      unless checklists_plugin? && issue.respond_to?(:issue_checklists)
        raise ToolError, 'Issue Checklists is not installed'
      end
      unless user.allowed_to?(:manage_issue_checklists, issue.project)
        raise ToolError, 'Not allowed to manage checklists on this issue'
      end
      raise ToolError, 'is_done is required' unless args.key?('is_done')

      item = find_checklist_item!(issue, args)
      done = flag!(args['is_done'])
      unless item.update(is_done: done)
        raise ToolError, item.errors.full_messages.join(', ').presence || 'Checklist item could not be updated'
      end

      checklist_payload(item)
    end

    def create_issue_from_template(args, user)
      raise ToolError, 'Plugin is in read-only mode' if Settings.read_only?
      raise ToolError, 'Issue Templates is not installed' unless templates_plugin?

      project = RedmineMcp::Tools.find_visible_project!(args['project_id'], user)
      require_template_access!(user, project)
      unless user.allowed_to?(:add_issues, project)
        raise ToolError, 'Not allowed to add issues on this project'
      end
      raise ToolError, 'template_id is required' if args['template_id'].blank?

      template = CommunityIssueTemplate.visible_for(project).find_by(id: args['template_id'])
      raise ToolError, 'Issue template not found or not usable' unless template

      overrides = override_hash(args['overrides'])
      payload = nil
      issue = nil
      checklist = nil

      with_user(user) do
        payload = RedmineIssueTemplates::ApplyPayload.build(
          template,
          project: project,
          user: user,
          current_tracker_id: overrides['tracker_id']
        )
        issue = build_issue_from_template(project, user, template, payload, overrides)
        unless issue.save
          raise ToolError, issue.errors.full_messages.join(', ').presence || 'Issue could not be created'
        end

        apply_watchers!(issue, project, user, payload)
        checklist = seed_checklist(issue, template, user)
      end

      {
        'id' => issue.id,
        'subject' => issue.subject,
        'project_id' => issue.project_id,
        'template_id' => template.id,
        'path' => "/issues/#{issue.id}",
        'ignored' => Array(payload[:ignored]),
        'checklist' => checklist
      }
    end

    private

    def templates_scope_for(user)
      ids = Project.visible(user).to_a.select { |project| template_access?(user, project) }.map(&:id)
      return CommunityIssueTemplate.none if ids.empty?

      project_ids = ids
      project_ids += [nil] if RedmineIssueTemplates.apply_global_templates?
      CommunityIssueTemplate.enabled.where(project_id: project_ids).order(:project_id, :position, :id)
    end

    def template_access?(user, project)
      project.module_enabled?(:issue_templates) && user.allowed_to?(:use_issue_templates, project)
    end

    def require_template_access!(user, project)
      unless project.module_enabled?(:issue_templates)
        raise ToolError, 'Issue Templates module is not enabled on this project'
      end
      unless user.allowed_to?(:use_issue_templates, project)
        raise ToolError, 'Not allowed to use issue templates on this project'
      end
    end

    def template_visible_to?(template, user)
      return false unless template&.enabled?

      if template.project_id
        project = Project.visible(user).find_by(id: template.project_id)
        project && template_access?(user, project)
      else
        RedmineIssueTemplates.apply_global_templates? &&
          Project.visible(user).any? { |project| template_access?(user, project) }
      end
    end

    def template_summary(template)
      {
        'id' => template.id,
        'title' => template.title,
        'subject' => template.subject.to_s,
        'project_id' => template.project_id,
        'global' => template.project_id.nil?,
        'tracker_ids' => template.template_trackers.order(:tracker_id, :id).pluck(:tracker_id)
      }
    end

    def tracker_payload(template)
      ids = template.template_trackers.order(:tracker_id, :id).pluck(:tracker_id)
      names = Tracker.where(id: ids).index_by(&:id)
      ids.filter_map { |id| names[id] }.map { |tracker| { 'id' => tracker.id, 'name' => tracker.name } }
    end

    def checklist_lines(template)
      return [] unless template.respond_to?(:checklist_items)

      template.checklist_items.to_s.split(/\r?\n/).filter_map do |line|
        text = line.to_s.strip
        text.empty? ? nil : text
      end
    end

    def whitelisted_custom_fields(template, user)
      return [] unless defined?(RedmineIssueTemplates::SafeCustomFields)

      raw = template.custom_field_values
      return [] if raw.blank?

      raw.filter_map do |key, value|
        next if value.is_a?(Array) || value.is_a?(Hash)

        field = IssueCustomField.find_by(id: key.to_i)
        next unless field
        next unless RedmineIssueTemplates::SafeCustomFields.safe_format?(field)
        next unless RedmineMcp::Tools.custom_field_visible?(field, user)

        { 'id' => field.id, 'name' => field.name, 'value' => value }
      end
    end

    # Redmine 7 names this permission :add_issue_notes. notes_addable? follows
    # the version that is actually loaded, including per-tracker limits.
    def notes_allowed?(user, issue)
      return issue.notes_addable?(user) if issue.respond_to?(:notes_addable?)

      user.allowed_to?(:add_issue_notes, issue.project) || user.allowed_to?(:add_notes, issue.project)
    end

    def visible_issue!(issue_id, user)
      raise ToolError, 'Issue is required' if issue_id.blank?

      issue = Issue.visible(user).find_by(id: issue_id)
      raise ToolError, 'Issue not found or not visible' unless issue

      issue
    end

    def find_checklist_item!(issue, args)
      if args['item_id'].present?
        item = issue.issue_checklists.find_by(id: args['item_id'])
        raise ToolError, 'Checklist item not found on this issue' unless item

        return item
      end

      if args['position'].present?
        item = issue.issue_checklists.find_by(position: args['position'].to_i)
        raise ToolError, 'Checklist item not found on this issue' unless item

        return item
      end

      raise ToolError, 'item_id or position is required'
    end

    def checklist_payload(item)
      done = item.respond_to?(:is_done?) ? item.is_done? : !!item.is_done
      {
        'id' => item.id,
        'issue_id' => item.issue_id,
        'position' => item.position,
        'subject' => item.subject,
        'is_done' => done
      }
    end

    def flag!(value)
      case value
      when TrueClass, FalseClass
        value
      when Integer
        !value.zero?
      when String
        normalized = value.strip.downcase
        unless %w[true false 1 0 yes no].include?(normalized)
          raise ToolError, 'is_done must be true or false'
        end

        %w[true 1 yes].include?(normalized)
      else
        raise ToolError, 'is_done must be true or false'
      end
    end

    def override_hash(raw)
      return {} if raw.nil?

      raise ToolError, 'overrides must be an object' unless raw.is_a?(Hash)

      overrides = raw.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
      unknown = overrides.keys - %w[subject description tracker_id]
      raise ToolError, "Unknown override keys: #{unknown.join(', ')}" if unknown.any?

      overrides
    end

    def build_issue_from_template(project, user, _template, payload, overrides)
      tracker_id = selected_tracker_id(project, payload, overrides)
      tracker = project.trackers.find_by(id: tracker_id)
      raise ToolError, 'Tracker is not enabled on this project' unless tracker

      subject = overrides.fetch('subject') { payload[:subject] }.to_s.strip
      raise ToolError, 'Subject is required' if subject.blank?

      description = if overrides.key?('description')
                      overrides['description'].to_s
                    else
                      payload[:description].to_s
                    end

      issue = Issue.new(
        project: project,
        tracker: tracker,
        author: user,
        subject: subject,
        description: description
      )
      issue.priority_id = payload[:priority_id].presence || IssuePriority.default&.id || IssuePriority.active.first&.id
      raise ToolError, 'No issue priority is available' if issue.priority_id.blank?

      issue.status = if payload[:status_id].present?
                       IssueStatus.find_by(id: payload[:status_id]) || tracker.default_status
                     else
                       tracker.default_status
                     end
      issue.assigned_to_id = payload[:assigned_to_id] if payload[:assigned_to_id].present?
      issue.category_id = payload[:category_id] if payload[:category_id].present?
      if payload[:builtin_fields].present?
        issue.custom_field_values = payload[:builtin_fields]
      end
      issue
    end

    def selected_tracker_id(project, payload, overrides)
      allowed = Array(payload[:tracker_ids]).map(&:to_i) & project.tracker_ids
      raise ToolError, 'Template has no tracker enabled on this project' if allowed.empty?

      if overrides['tracker_id'].present?
        requested = overrides['tracker_id'].to_i
        unless allowed.include?(requested)
          raise ToolError, 'Tracker override is not allowed for this template on this project'
        end

        return requested
      end

      suggested = payload[:tracker_id].to_i
      allowed.include?(suggested) ? suggested : allowed.first
    end

    def apply_watchers!(issue, project, user, payload)
      watcher_ids = Array(payload[:watcher_user_ids]).map(&:to_i).select(&:positive?)
      return if watcher_ids.empty?
      return payload[:ignored] << 'watcher_user_ids' unless user.allowed_to?(:add_issue_watchers, project)

      watcher_ids.each do |watcher_id|
        watcher = User.active.find_by(id: watcher_id)
        issue.add_watcher(watcher) if watcher
      end
    rescue StandardError
      payload[:ignored] << 'watcher_user_ids'
    end

    def seed_checklist(issue, template, user)
      lines = checklist_lines(template)
      unless checklists_plugin? && issue.respond_to?(:issue_checklists)
        return { 'seeded' => false, 'reason' => 'Issue Checklists is not installed' }
      end
      unless user.allowed_to?(:manage_issue_checklists, issue.project)
        return { 'seeded' => false, 'reason' => 'Not allowed to manage checklists' }
      end
      if lines.empty?
        return { 'seeded' => false, 'reason' => 'Template has no checklist lines' }
      end

      before = issue.issue_checklists.count
      RedmineIssueTemplates::ChecklistSeed.call(
        issue,
        { 'community_issue_template_id' => template.id }
      )
      issue.issue_checklists.reload
      if issue.issue_checklists.count > before
        { 'seeded' => true, 'count' => issue.issue_checklists.count }
      else
        { 'seeded' => false, 'reason' => 'Checklist lines were not copied' }
      end
    end

    def with_user(user)
      previous = User.current
      User.current = user
      yield
    ensure
      User.current = previous
    end
  end
end
