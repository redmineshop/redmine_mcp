# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  match 'mcp', to: 'mcp#handle', via: %i[get post], as: :redmine_mcp
end
