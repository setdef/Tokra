# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Resources plugin adapted from tauri/crates/tauri/src/resources/plugin.rs

module Tokra
  # Namespace for the resource lifecycle core plugin.
  #
  # Mirrors Tauri's resources module (resources/mod.rs and
  # resources/plugin.rs). The ResourceTable and Resource primitives
  # live at the Tokra top level, matching Tauri's crate-root re-exports.
  module Resources
    # Core plugin handling resource lifecycle IPC commands.
    #
    # Resources pile up unless the frontend can release them. Tauri's
    # JavaScript Resource class calls <tt>plugin:resources|close</tt>
    # when frontend code finishes with a rid.
    #
    # This plugin answers that command, searching the same three tables
    # as Tauri's resources/plugin.rs: webview, then window, then app.
    # Tokra registers it automatically.
    class Plugin < Tokra::Plugin
      # Returns the plugin identifier.
      def name
        "resources"
      end

      # Handles IPC commands for resource management.
      #
      # Receives the bare command name: the IPC dispatcher strips the
      # <tt>plugin:resources|</tt> prefix before routing, exactly as Tauri
      # rewrites +invoke.message.command+ in webview/mod.rs.
      #
      # Reads +rid+ as Tauri's ResourceId, a u32, so a missing or non-u32
      # rid rejects with Tauri's <tt>invalid args `rid` for command
      # `close`</tt> message; any other error is a bug, and reaches the
      # router.
      #
      # Returns +true+ if the command was handled, +false+ otherwise.
      def extend_api(invoke)
        return false unless invoke.command == "close"

        begin
          rid = Ipc::CommandItem.new(name: invoke.command, key: "rid", payload: invoke.body).u32
        rescue Error::InvalidArgs => e
          invoke.reject(e.message)
          return true
        end

        # 3-level fallback matching Tauri resources/plugin.rs:15-22
        # Final error propagates if all levels fail
        result = try_close(invoke.webview, rid)
        result = try_close(invoke.webview.window, rid) if result.is_a?(Error::BadResourceId)
        result = try_close(invoke.webview.app_handle, rid) if result.is_a?(Error::BadResourceId)

        if result.is_a?(Error::BadResourceId)
          invoke.reject(result.message)
        else
          invoke.resolve(nil)
        end
        true
      end

      # Attempts to close a resource at the given manager level.
      #
      # Returns +nil+ on success, or the BadResourceId error on failure.
      private def try_close(manager, rid)
        manager.resources_table.close(rid)
        nil
      rescue Error::BadResourceId => e
        e
      end
    end
  end
end

# SPDX-SnippetEnd
