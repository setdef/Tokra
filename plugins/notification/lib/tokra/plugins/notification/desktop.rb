# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Notification and imp::Notification adapted from
#                      tauri-plugin-notification src/desktop.rs;
#                      NotificationExt from src/lib.rs:210-219

module Tokra
  module Plugins
    module Notification
      # The notifications an app shares through managed state.
      #
      # Commands, menu handlers, and background jobs all tell the user
      # things, and each needs the app's configuration to name the app the
      # notification comes from.
      #
      # The plugin manages one Notification at registration, so every
      # manager reaches it as +notification+. Ask it for a #builder, or for
      # the permission state, which on desktop is always granted.
      #
      # Mirrors Tauri's desktop <tt>Notification</tt> (desktop.rs:13-68).
      #
      # === Example
      #
      #   handle.notification.builder.title("Hello").show
      class Notification
        # The app handle the notifications read their configuration from.
        attr_reader :app_handle

        # Creates the notifications for +app_handle+. The plugin does this
        # once and manages the result (desktop.rs:13-18).
        #
        # [app_handle] the Tokra::AppHandle.
        def initialize(app_handle)
          @app_handle = app_handle
        end

        # A new NotificationBuilder (desktop.rs:57-59).
        #
        # === Example
        #
        #   handle.notification.builder.title("Saved").show
        def builder
          NotificationBuilder.new(@app_handle)
        end

        # Asks the user for permission to show notifications. Desktop
        # systems do not ask, so this answers PermissionState::Granted, as
        # Tauri's desktop plugin does (desktop.rs:61-63).
        #
        # === Example
        #
        #   handle.notification.request_permission  #=> Tokra::PermissionState::Granted
        def request_permission
          PermissionState::Granted
        end

        # Whether the app may show notifications: PermissionState::Granted
        # on desktop (desktop.rs:65-67).
        #
        # === Example
        #
        #   handle.notification.permission_state  #=> Tokra::PermissionState::Granted
        def permission_state
          PermissionState::Granted
        end
      end

      # Gives every manager a +notification+ method.
      #
      # When included into Tokra::Manager, an app handle, window, or webview
      # reaches the managed Notification directly:
      #
      #   handle.notification.builder.title("Hi").show
      #
      # Mirrors Tauri's <tt>NotificationExt</tt> blanket implementation
      # (lib.rs:210-219).
      module NotificationExt
        # The Notification the plugin manages. Raises +KeyError+ before the
        # plugin is registered.
        #
        # === Example
        #
        #   handle.notification.permission_state
        def notification
          state(Notification)
        end
      end

      # Tauri's private desktop implementation (desktop.rs:70-289).
      module Imp # :nodoc:
        # The desktop notification: what Tauri hands notify-rust, and how
        # it sends it (desktop.rs:99-221).
        class Notification # :nodoc:
          # The identifier of the app the notification comes from.
          attr_reader :identifier

          # A notification for the app with +identifier+ (desktop.rs:115-121).
          def initialize(identifier)
            @identifier = identifier
          end

          # Sets the body (desktop.rs:123-128).
          def body(body)
            with(:@body, body)
          end

          # Sets the title (desktop.rs:130-135).
          def title(title)
            with(:@title, title)
          end

          # Sets the icon (desktop.rs:137-142).
          def icon(icon)
            with(:@icon, icon)
          end

          # Sets the sound (desktop.rs:144-149).
          def sound(sound)
            with(:@sound, sound)
          end

          # The notify-rust notification Tauri builds: the body, the title
          # as summary, the icon or notify-rust's own, and the sound
          # (desktop.rs:180-194). Windows takes no app ID; see Plugin.
          def to_notify_rust
            notification = Ferro::NotifyRust::Notification.new
            notification.body(@body) if @body
            notification.summary(@title) if @title
            @icon ? notification.icon(@icon) : notification.auto_icon
            notification.sound_name(@sound) if @sound
            notification
          end

          # Names the app on macOS, ignoring the answer, as Tauri does
          # (desktop.rs:207-214). Tokra serves its pages through its own
          # protocol, as Tauri's release builds do, so this is the
          # identifier, never the development builds' Terminal.
          def name_application
            return unless Ferro::NotifyRust.respond_to?(:set_application)

            Ferro::NotifyRust.set_application(@identifier)
          rescue Ferro::NotifyRust::Error
            nil
          end

          # Builds the notification, names the app, and sends it on a new
          # thread, dropping a failure (desktop.rs:179-221). Returns the
          # thread.
          def show
            notification = to_notify_rust
            name_application
            Thread.new do
              notification.show
              nil
            rescue Ferro::NotifyRust::Error
              nil
            end
          end

          private def with(name, value)
            copy = dup
            copy.instance_variable_set(name, value)
            copy
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
