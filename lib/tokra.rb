# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tokra/version"
require "erb"
require "json"
require "securerandom"
require_relative "tokra/error"
require_relative "tokra/resource"
require_relative "tokra/image"
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
require_relative "tokra/z85"
require_relative "tokra/ipc/invoke"
require_relative "tokra/ipc/format_callback"
require_relative "tokra/builder"
require_relative "tokra/plugin"
require_relative "tokra/plugin_api"
require_relative "tokra/state_manager"
require_relative "tokra/resource_table"
require_relative "tokra/resources/plugin"
require_relative "tokra/image/plugin"
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
  # Mix Manager into native classes for Tauri parity.
  # In Tauri, Manager is implemented for AppHandle, Window, Webview, and App.
  Native::Window.include(Manager)
  Native::WebView.include(Manager)

  # Generates the per-app IPC invoke key: 16 random bytes, Z85-encoded.
  #
  # The key is templated into the injected initialization scripts and
  # verified on every IPC message, so only frames the app initialized
  # can invoke commands. Mirrors Tauri's generate_invoke_key (lib.rs).
  def self.generate_invoke_key
    Z85.encode(SecureRandom.random_bytes(16))
  end
end
