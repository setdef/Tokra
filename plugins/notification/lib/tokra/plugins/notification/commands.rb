# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Commands adapted from tauri-plugin-notification
#                      src/commands.rs

module Tokra
  module Plugins
    module Notification
      # The plugin's IPC commands: is_permission_granted,
      # request_permission, and notify.
      #
      # Each answers the frontend the way Tauri's desktop plugin does.
      # Permission is always granted on desktop. +notify+ reads its options
      # as Tauri deserializes them, rejecting a bad one with Tauri's
      # message, and shows the notification without waiting for it to
      # arrive, so the invoke settles at once and the event loop never
      # waits on the notification server.
      #
      # These are the functions of Tauri's private +commands+ module
      # (commands.rs). Plugin#extend_api calls them.
      module Commands
        # Settles +invoke+ with whether notifications are allowed: +true+
        # for granted, +false+ for denied, +nil+ while the user has not
        # been asked (commands.rs:9-20).
        #
        # === Example
        #
        #   Commands.is_permission_granted(invoke, handle.notification)
        def self.is_permission_granted(invoke, notification)
          state = notification.permission_state
          granted = case state
          when PermissionState::Granted then true
          when PermissionState::Denied then false
          end
          invoke.resolve(granted)
        end

        # Settles +invoke+ with the permission state after asking
        # (commands.rs:22-28).
        #
        # === Example
        #
        #   Commands.request_permission(invoke, handle.notification)
        def self.request_permission(invoke, notification)
          invoke.resolve(notification.request_permission)
        end

        # Shows the notification the frontend describes and settles
        # +invoke+ with +nil+ (commands.rs:30-39).
        #
        # === Example
        #
        #   Commands.notify(invoke, handle.notification)
        def self.notify(invoke, notification)
          options = Arguments.new(invoke.body, "notify").notification_data
          builder = notification.builder
          builder.data = options
          builder.show
          invoke.resolve(nil)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
