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
require "uri"
require_relative "tokra/error"
require_relative "tokra/raw_window_handle"
require_relative "tokra/resource"
require_relative "tokra/image"
require_relative "tokra/native"
require_relative "tokra/native/events"
require_relative "tokra/exit_request_api"
require_relative "tokra/close_request_api"
require_relative "tokra/run_event"
require_relative "tokra/window_event"
require_relative "tokra/page_load_payload"
require_relative "tokra/env"
require_relative "tokra/process"
require_relative "tokra/manager"
require_relative "tokra/config"
require_relative "tokra/app_manager"
require_relative "tokra/runtime_context"
require_relative "tokra/app_handle"
require_relative "tokra/app"
require_relative "tokra/uri_scheme_context"
require_relative "tokra/uri_scheme_responder"
require_relative "tokra/response"
require_relative "tokra/z85"
require_relative "tokra/ipc/invoke_body"
require_relative "tokra/ipc/invoke"
require_relative "tokra/ipc/request"
require_relative "tokra/ipc/response"
require_relative "tokra/ipc/invoke_error"
require_relative "tokra/ipc/format_callback"
require_relative "tokra/ipc/unexpected"
require_relative "tokra/ipc/json"
require_relative "tokra/ipc/command_item"
require_relative "tokra/builder"
require_relative "tokra/plugin"
require_relative "tokra/ipc/channel"
require_relative "tokra/plugin_api"
require_relative "tokra/permission_state"
require_relative "tokra/state_manager"
require_relative "tokra/resource_table"
require_relative "tokra/resources/plugin"
require_relative "tokra/image/plugin"
require_relative "tokra/window"
require_relative "tokra/webview"
require_relative "tokra/path/resolver"
require_relative "tokra/dpi"
require_relative "tokra/physical_position"
require_relative "tokra/logical_position"
require_relative "tokra/physical_size"
require_relative "tokra/logical_size"
require_relative "tokra/physical_rect"
require_relative "tokra/logical_unit"
require_relative "tokra/physical_unit"
require_relative "tokra/window_size_constraints"
require_relative "tokra/color"
require_relative "tokra/monitor"
require_relative "tokra/theme"
require_relative "tokra/cursor_icon"
require_relative "tokra/user_attention_type"
require_relative "tokra/resize_direction"
require_relative "tokra/drag_drop_event"
require_relative "tokra/webview_event"
# On Windows the extension imports WebView2Loader.dll, which its build
# installs beside it (ext/tokra/extconf.rb), and Windows does not look for an
# extension's DLLs in the extension's own directory. RubyInstaller limits the
# search to the directories it sets up and those added with
# add_dll_directory (AddDllDirectory; rubyinstaller2
# lib/ruby_installer/build/dll_directory.rb), so the directory is added
# there, or to PATH for a Ruby without RubyInstaller.
if RUBY_PLATFORM.match?(/mingw|mswin/)
  native_dir = File.expand_path("tokra", __dir__.to_s)
  if Object.const_defined?("RubyInstaller::Runtime")
    Object.const_get("RubyInstaller::Runtime").__send__(:add_dll_directory, native_dir)
  else
    ENV["PATH"] = "#{native_dir}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}"
  end
end
require_relative "tokra/tokra"
# The menu classes ask the extension which platform calls it defines.
require_relative "tokra/menu"
require_relative "tokra/menu_manager"
require_relative "tokra/activation_policy"
require_relative "tokra/rack/handler"

# Tokra is a port of Tauri to Ruby.
module Tokra
  # Generates the per-app IPC invoke key: 16 random bytes, Z85-encoded.
  #
  # The key is templated into the injected initialization scripts and
  # verified on every IPC message, so only frames the app initialized
  # can invoke commands. Mirrors Tauri's generate_invoke_key (lib.rs).
  def self.generate_invoke_key
    Z85.encode(SecureRandom.random_bytes(16))
  end
end
