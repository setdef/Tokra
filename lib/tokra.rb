# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tokra/version"
require "json"
require_relative "tokra/native"
require_relative "tokra/native/events"
require_relative "tokra/run_event"
require_relative "tokra/window_event"
require_relative "tokra/page_load_payload"
require_relative "tokra/manager"
require_relative "tokra/config"
require_relative "tokra/app_manager"
require_relative "tokra/app_handle"
require_relative "tokra/app"
require_relative "tokra/uri_scheme_context"
require_relative "tokra/uri_scheme_responder"
require_relative "tokra/response"
require_relative "tokra/invoke"
require_relative "tokra/builder"
require_relative "tokra/plugin"
require_relative "tokra/plugin_api"
require_relative "tokra/state_manager"
require_relative "tokra/resource_table"
require_relative "tokra/window"
require_relative "tokra/webview"
require_relative "tokra/path/resolver"
require_relative "tokra/physical_position"
require_relative "tokra/drag_drop_event"
require_relative "tokra/webview_event"
require_relative "tokra/tokra"
require_relative "tokra/rack/handler"

# Tokra is a port of Tauri to Ruby.
module Tokra
  # Base error class for all Tokra errors.
  class Error < StandardError; end

  # Mix Manager into native classes for Tauri parity.
  # In Tauri, Manager is implemented for AppHandle, Window, Webview, and App.
  Native::Window.include(Manager)
  Native::WebView.include(Manager)
end
