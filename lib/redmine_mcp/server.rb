# frozen_string_literal: true

module RedmineMcp
  class Server
    def initialize(user:)
      @user = user
    end

    def handle(payload)
      unless payload.is_a?(Hash)
        return Protocol.error(nil, -32600, 'Invalid Request')
      end

      method = payload['method']
      params = payload['params'] || {}
      has_id = payload.key?('id')
      id = payload['id']

      unless payload['jsonrpc'] == '2.0' && method.is_a?(String)
        return notification?(has_id) ? nil : Protocol.error(id, -32600, 'Invalid Request')
      end

      params = {} if params.nil?
      unless params.is_a?(Hash)
        return notification?(has_id) ? nil : Protocol.error(id, -32602, 'Invalid params')
      end

      result = dispatch(method, params)
      return nil if notification?(has_id)

      Protocol.result(id, result)
    rescue ToolError => e
      return nil if notification?(has_id)

      if method.to_s == 'tools/call'
        Protocol.result(
          id,
          {
            'content' => [{ 'type' => 'text', 'text' => Protocol.sanitize(e.message) }],
            'isError' => true
          }
        )
      else
        Protocol.error(id, e.code, e.message)
      end
    rescue StandardError => e
      Rails.logger.error("[redmine_mcp] #{e.class}: #{Protocol.sanitize(e.message)}")
      return nil if notification?(has_id)

      Protocol.error(id, -32603, 'Internal error')
    end

    private

    def notification?(has_id)
      !has_id
    end

    def dispatch(method, params)
      case method
      when 'initialize'
        initialize_session(params)
      when 'notifications/initialized', 'initialized'
        {}
      when 'ping'
        {}
      when 'tools/list'
        list_tools
      when 'tools/call'
        call_tool(params)
      else
        raise ToolError.new("Method not found: #{method}", code: -32601)
      end
    end

    def initialize_session(params)
      {
        'protocolVersion' => Protocol.negotiate_version(params['protocolVersion']),
        'capabilities' => { 'tools' => { 'listChanged' => false } },
        'serverInfo' => { 'name' => 'redmine-mcp', 'version' => VERSION },
        'instructions' => 'Redmine MCP. Tools run as the API key user with Redmine permissions. ' \
                          'Read-only mode hides write tools: wiki update, issue notes, checklist ticks, ' \
                          'and create issue from a template.'
      }
    end

    def list_tools
      {
        'tools' => ToolRegistry.visible(read_only: Settings.read_only?).map do |tool|
          {
            'name' => tool.name,
            'description' => tool.description,
            'inputSchema' => tool.input_schema
          }
        end
      }
    end

    def call_tool(params)
      name = params['name'].to_s
      arguments = params['arguments'] || {}
      arguments = {} if arguments.nil?
      raise ToolError, 'Tool name is required' if name.blank?
      raise ToolError, 'Tool arguments must be an object' unless arguments.is_a?(Hash)

      tool = ToolRegistry.find(name, read_only: Settings.read_only?)
      unless tool
        raise ToolError, Settings.read_only? && write_tool?(name) ?
          'Write tools are hidden while the plugin is in read-only mode' :
          "Unknown tool: #{name}"
      end

      payload = Tools.public_send(tool.handler, stringify_keys(arguments), @user)
      {
        'content' => [{ 'type' => 'text', 'text' => JSON.pretty_generate(payload) }]
      }
    end

    def write_tool?(name)
      ToolRegistry.all.any? { |tool| tool.name == name && tool.write }
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
    end
  end
end
