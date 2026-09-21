# frozen_string_literal: true

class McpController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_parse_error
  before_action :reject_get
  before_action :require_mcp_enabled
  before_action :require_rest_api_enabled
  before_action :authenticate_mcp_user

  def handle
    payload = parse_json_body
    if payload.is_a?(Array)
      render json: RedmineMcp::Protocol.error(nil, -32600, 'Batch requests are not supported'),
             status: :bad_request
      return
    end

    result = RedmineMcp::Server.new(user: User.current).handle(payload)
    if result.nil?
      head :no_content
    else
      render json: result
    end
  rescue RedmineMcp::ParseError
    render json: RedmineMcp::Protocol.error(nil, -32700, 'Parse error'), status: :bad_request
  end

  private

  def reject_get
    return unless request.get?

    response.set_header('Allow', 'POST')
    render json: RedmineMcp::Protocol.error(nil, -32600, 'MCP accepts POST only'), status: :method_not_allowed
  end

  def require_mcp_enabled
    return if RedmineMcp::Settings.enabled?

    log_event('disabled')
    render json: RedmineMcp::Protocol.error(nil, -32001, 'MCP endpoint is disabled'), status: :forbidden
  end

  def require_rest_api_enabled
    return if Setting.rest_api_enabled?

    log_event('rest_api_disabled')
    render json: RedmineMcp::Protocol.error(nil, -32001, 'Enable Redmine REST API to use MCP (Administration → Settings → API)'),
           status: :forbidden
  end

  def authenticate_mcp_user
    key = api_key_from_request
    user = key.present? ? User.find_by_api_key(key) : nil
    unless user&.active?
      log_event('unauthorized')
      render json: RedmineMcp::Protocol.error(nil, -32001, 'Invalid or missing API key'), status: :unauthorized
      return
    end

    User.current = user
    log_event(request_method_name)
  end

  def api_key_from_request
    header = request.headers['X-Redmine-API-Key'].presence
    return header if header

    auth = request.authorization.to_s.presence || request.headers['Authorization'].to_s
    if auth.start_with?('Bearer ')
      token = auth.split(' ', 2).last.to_s.strip
      return token if token.present?
    end

    params[:key].presence
  end

  def parse_json_body
    raw = request.raw_post
    raise RedmineMcp::ParseError if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    raise RedmineMcp::ParseError
  end

  def render_parse_error(_exception = nil)
    render json: RedmineMcp::Protocol.error(nil, -32700, 'Parse error'), status: :bad_request
  end

  def request_method_name
    JSON.parse(request.raw_post.to_s)['method']
  rescue StandardError
    'unknown'
  end

  def log_event(event)
    Rails.logger.info("[redmine_mcp] event=#{event} user=#{User.current&.id}")
  end
end
