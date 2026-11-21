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

# Desktop notifications, through notify-rust; attachment URLs, through url;
# and scheduled dates, through time (ADR 020). A failure to load any of
# them is a real installation problem, so its LoadError propagates as-is.
require "ferro/notify_rust"
require "ferro/time"
require "ferro/url"

require_relative "notification/version"
require_relative "notification/models"
require_relative "notification/notification_builder"
require_relative "notification/desktop"
require_relative "notification/commands"
require_relative "notification/arguments"

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
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
    # With <tt>app.withGlobalTauri</tt> in your config, a page with no
    # bundler finds the same functions on
    # <tt>window.__TAURI__.notification</tt>: the plugin ships Tauri's own
    # <tt>api-iife.js</tt>, which every page runs after Tauri's bundle.
    # Require <tt>tokra-notification</tt> before Tokra.generate_context
    # reads it.
    #
    # == Ruby API
    #
    # Register the plugin on the builder with ::init. It manages a
    # Notification, which every manager reaches as +notification+:
    #
    #   require "tokra-notification"
    #
    #   Tokra::Builder.default
    #     .plugin(Tokra::Plugins::Notification.init)
    #     .run(Tokra.generate_context)
    #
    # The plugin takes no config: a non-null <tt>plugins.notification</tt>
    # in your config fails the app with Error::PluginInitialization, as
    # Tauri's does.
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
    # * A notification's options are checked as Tauri checks them, except
    #   that an attachment URL's domain meets Unicode 18.0's international
    #   domain name tables, where Tauri's are Unicode 15.1's: a domain
    #   holding a character Unicode assigned since 15.1, or one of 66
    #   older ones the newer tables accept (such as Georgian capital
    #   letters, U+10A0 to U+10C5, and the Hangul fillers), can parse, or
    #   fail later with another error such as "invalid IPv4 address",
    #   where Tauri answers "invalid international domain name", though
    #   some newly assigned characters still fail in both; that a
    #   scheduled date is read by time 0.3.55, where Tauri's is 0.3.41, so
    #   a date component out of range reads "day was not in range" where
    #   Tauri gives the range, an offset of 24 or 25 hours parses where
    #   Tauri refuses it, and a date starting with "T" fails with another
    #   message; that <tt>-0</tt> reads as the integer 0 (serde_json
    #   reads a float, so Tauri rejects it as an +id+); and that a float
    #   with more digits than a double holds may print differently in its
    #   last digit in a type error.
    #
    # Mirrors Tauri's notification plugin (lib.rs:221-242).
    module Notification
      # Tauri's permission state, which the plugin answers with
      # (lib.rs:23).
      PermissionState = Tokra::PermissionState

      # Tauri's init script, unchanged, with <tt>__TEMPLATE_windows__</tt>
      # replaced as Tauri replaces it: +true+ on Windows, +false+
      # elsewhere (lib.rs:229-232). It gives the page a
      # <tt>window.Notification</tt> that calls the plugin's commands
      # (src/init-iife.js, built from guest-js/init.ts).
      INIT_SCRIPT = File.read(File.expand_path("notification/init-iife.js", __dir__))
        .gsub("__TEMPLATE_windows__", Gem.win_platform? ? "true" : "false").freeze

      # The commands the plugin answers on desktop (lib.rs:224-228).
      COMMANDS = %w[notify request_permission is_permission_granted].freeze

      # Initializes the plugin: a Tokra::Plugin::TauriPlugin named
      # +notification+, the name in <tt>plugin:notification|notify</tt>,
      # for Tokra::Builder#plugin.
      #
      # Every page runs its init script after Tauri's own. Its setup
      # manages a Notification for the app (a second plugin finds one
      # already managed and shares it). It answers the notify,
      # request_permission, and is_permission_granted commands, and leaves
      # any other for the router, which rejects it with <tt>Command NAME
      # not found</tt>, as Tauri does for the commands only its mobile
      # plugins answer. An argument that does not read rejects the invoke
      # with Tauri's message; anything else is a bug, and reaches the
      # router.
      #
      # Mirrors Tauri's <tt>init</tt> (lib.rs:221-242).
      #
      # === Example
      #
      #   Tokra::Builder.default.plugin(Tokra::Plugins::Notification.init)
      def self.init
        Tokra::Plugin::Builder.new("notification")
          .invoke_handler { |invoke| handle_invoke(invoke) }
          .js_init_script(INIT_SCRIPT)
          .setup { |app, _api| app.manage(Notification.new(app)) }
          .build
      end

      # Runs one of COMMANDS against the Notification the invoking
      # webview's app manages, as Tauri's commands take it as State;
      # answers whether it was one of them.
      def self.handle_invoke(invoke) # :nodoc:
        command = invoke.command
        return false unless COMMANDS.include?(command)

        notification = invoke.webview.app_handle.notification
        case command
        when "notify" then Commands.notify(invoke, notification)
        when "request_permission" then Commands.request_permission(invoke, notification)
        else Commands.is_permission_granted(invoke, notification)
        end
        true
      rescue Tokra::Error::InvalidArgs => e
        invoke.reject(e.message)
        true
      end
      private_class_method :handle_invoke
    end
  end
end

# Tauri's own global API script for the plugin, which defines
# window.__TAURI__.notification in a page with withGlobalTauri (build.rs;
# api-iife.js at plugins-workspace d4613ff0, unchanged).
Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("notification/api-iife.js", __dir__))

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Notification::NotificationExt)

# SPDX-SnippetEnd
