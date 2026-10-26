# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Plugin adapted from tauri-plugin-notification src/lib.rs:221-242

require "tokra"

# Desktop notifications, through notify-rust (ADR 011). A failure to load
# it is a real installation problem, so its LoadError propagates as-is.
require "ferro/notify_rust"

require_relative "notification/version"
require_relative "notification/models"
require_relative "notification/iso8601"
require_relative "notification/url_check"
require_relative "notification/notification_builder"
require_relative "notification/desktop"
require_relative "notification/commands"
require_relative "notification/arguments"

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
    # Namespace for the notification plugin.
    #
    # Use Tokra::Plugins::Notification::Plugin as the plugin class.
    module Notification
      # Tauri's permission state, which the plugin answers with
      # (lib.rs:23).
      PermissionState = Tokra::PermissionState

      # Desktop notifications for Tokra applications.
      #
      # An app that finishes a long job, or hears about something the user
      # cares about, should say so where the user looks: a notification in
      # the corner of the screen. Each system shows them its own way, and
      # the page's <tt>window.Notification</tt> shows none inside a
      # webview.
      #
      # This plugin shows them through ferro-notify-rust, a one-to-one Ruby
      # binding of the notify-rust crate, and serves the desktop commands
      # of Tauri's notification plugin, so the frontend uses
      # <tt>@tauri-apps/plugin-notification</tt> unchanged. Its init script
      # also gives the page a <tt>window.Notification</tt> that shows the
      # system's notifications, as Tauri's does.
      #
      # == JavaScript API (Tauri Compatibility)
      #
      #   import { isPermissionGranted, requestPermission, sendNotification } from '@tauri-apps/plugin-notification';
      #
      #   let granted = await isPermissionGranted();          // true on desktop
      #   if (!granted) granted = (await requestPermission()) === 'granted';
      #   if (granted) sendNotification({ title: 'Tokra', body: 'Build finished', sound: 'Ping' });
      #   new Notification('Tokra', { body: 'Also works' });
      #
      # On desktop a notification uses its title, body, icon, and sound,
      # as in Tauri; the other options are checked and kept, but only
      # mobile systems read them. Options are checked the way Tauri
      # deserializes them: a bad one rejects with Tauri's message, for
      # example <tt>invalid args `options` for command `notify`: invalid
      # type: floating point `1.5`, expected i32</tt>. The mobile-only
      # functions (+registerActionTypes+, +pending+, +cancel+, +active+,
      # +removeActive+, the channel functions, +onNotificationReceived+,
      # and +onAction+) reject with <tt>Command NAME not found</tt>, as
      # they do in Tauri on desktop.
      #
      # Tauri also defines <tt>window.__TAURI__.notification</tt> when the
      # app sets +withGlobalTauri+. Tokra has no plugin global scripts
      # yet, so import the package through your bundler.
      #
      # == Ruby API
      #
      # Register the plugin on the app handle, for example in the setup
      # hook. It manages a Notification, which every manager reaches as
      # +notification+:
      #
      #   Tokra::Builder.new
      #     .setup { |app| app.handle.plugin(Tokra::Plugins::Notification::Plugin.new(app.handle)) }
      #     .run
      #
      #   handle.notification.builder.title("Saved").body("Your draft is safe.").show
      #
      # NotificationBuilder#show returns at once; the notification goes out
      # on a thread of its own, and a failure to send it is dropped, as in
      # Tauri. Every send gets a new thread, and an app that exits waits
      # for one still under way, on macOS for up to about two seconds.
      #
      # == The app a notification comes from
      #
      # On macOS the first notification names the app it comes from by the
      # app's identifier, through notify-rust's +set_application+. An app
      # run from source has no installed bundle with that identifier, so
      # its notifications come from Terminal, as a Tauri app's do in
      # development; an app bundle with that identifier shows its own name
      # and icon. notify-rust sets this once for the whole process, by
      # changing what the process reports as its bundle identifier, and
      # the first call wins: if your code calls
      # <tt>Ferro::NotifyRust.set_application</tt> first, its choice
      # stays. No other library in the process may link notify-rust or
      # mac-notification-sys.
      #
      # On Windows a toast names no app, so it comes from PowerShell, as a
      # Tauri app's do in development. Tauri names the installed app; no
      # installer registers a Tokra app yet.
      #
      # == Deviations
      #
      # * Windows toasts come from PowerShell, and Windows 7, which Rust no
      #   longer builds for, gets none.
      # * Without a configured identifier, macOS notifications come from
      #   Terminal.
      # * A notification's options are checked as Tauri checks them, except
      #   that an attachment URL whose host has non-ASCII characters or an
      #   <tt>xn--</tt> label is not run through international domain name
      #   rules, that <tt>-0</tt> reads as the integer 0 (serde_json reads a
      #   float, so Tauri rejects it as an +id+), and that a float with more
      #   digits than a double holds may print differently in its last
      #   digit in a type error.
      # * <tt>window.__TAURI__.notification</tt> is not defined.
      #
      # Mirrors Tauri's notification plugin (lib.rs:221-242).
      class Plugin < Tokra::Plugin
        # Tauri's init script, unchanged, with <tt>__TEMPLATE_windows__</tt>
        # replaced as Tauri replaces it: +true+ on Windows, +false+
        # elsewhere (lib.rs:229-232). It gives the page a
        # <tt>window.Notification</tt> that calls the plugin's commands
        # (src/init-iife.js, built from guest-js/init.ts).
        INIT_SCRIPT = File.read(File.expand_path("notification/init-iife.js", __dir__))
          .gsub("__TEMPLATE_windows__", Gem.win_platform? ? "true" : "false").freeze

        # The commands the plugin answers on desktop (lib.rs:224-228).
        COMMANDS = %w[notify request_permission is_permission_granted].freeze

        # Returns the unique plugin identifier, "notification"
        # (lib.rs:223), the name in <tt>plugin:notification|notify</tt>.
        def name
          "notification"
        end

        # Registers the plugin with +app+, the app handle, and manages a
        # Notification for it, the body of Tauri's setup closure
        # (lib.rs:233-240). A second plugin instance finds a Notification
        # already managed and shares it.
        #
        #   handle.plugin(Tokra::Plugins::Notification::Plugin.new(handle))
        def initialize(app, config = {})
          super
          app.manage(Notification.new(app))
        end

        # Tauri's init script, which every page runs after Tauri's own
        # (lib.rs:229-232).
        def initialization_script
          INIT_SCRIPT
        end

        # Handles the notify, request_permission, and is_permission_granted
        # commands.
        #
        # Returns +true+ for one of the plugin's commands and +false+ for
        # any other, so Tokra rejects the rest with <tt>Command NAME not
        # found</tt>, as Tauri does for the commands only its mobile
        # plugins answer.
        def extend_api(invoke)
          command = invoke.command
          return false unless COMMANDS.include?(command)

          notification = app.notification
          case command
          when "notify" then Commands.notify(invoke, notification)
          when "request_permission" then Commands.request_permission(invoke, notification)
          else Commands.is_permission_granted(invoke, notification)
          end
          true
        rescue ArgumentError => e
          invoke.reject(e.message)
          true
        end
      end
    end
  end
end

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Notification::NotificationExt)

# SPDX-SnippetEnd
