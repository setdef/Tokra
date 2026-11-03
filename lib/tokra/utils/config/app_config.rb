# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AppConfig adapted from tauri-utils src/config.rs:2687-2766
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # What your app is while it runs: its windows, its security, its
      # tray icon, and its global API.
      #
      # The <tt>app</tt> key of the config gathers what the running app
      # reads, apart from how it is built and bundled. Its windows open
      # when the app starts; its security settings limit its pages.
      #
      # Tokra reads every key now. The windows and <tt>withGlobalTauri</tt>
      # act once the builder takes a context; the tray icon in plan 054's
      # third phase; <tt>enableGTKAppId</tt> in its fourth; and
      # <tt>macOSPrivateApi</tt> with plan 052's question 2.
      #
      # Mirrors Tauri's <tt>AppConfig</tt> (config.rs:2687-2766).
      #
      # === Example
      #
      #   app = Tokra.generate_context.config.app
      #   app.windows.map(&:label)  #=> ["main"]
      #   app.with_global_tauri     #=> false
      class AppConfig < Data.define(
        :windows, :security, :tray_icon, :macos_private_api, :with_global_tauri, :enable_gtk_app_id
      )
        BOOL = -> (raw) { Ipc::Serde.boolean(raw) } # :nodoc:
        private_constant :BOOL

        FIELDS = [
          Field.defaulted(:windows, "windows", -> (raw) { Utils::Config.sequence(raw) { |window| WindowConfig.deserialize(window) } },
            []),
          Field.defaulted(:security, "security", -> (raw) { SecurityConfig.deserialize(raw) }, SecurityConfig.new),
          Field.option(:tray_icon, "trayIcon", -> (raw) { TrayIconConfig.deserialize(raw) }, aliases: %w[tray-icon]),
          Field.defaulted(:macos_private_api, "macOSPrivateApi", BOOL, false, aliases: %w[macos-private-api]),
          Field.defaulted(:with_global_tauri, "withGlobalTauri", BOOL, false, aliases: %w[with-global-tauri]),
          Field.defaulted(:enable_gtk_app_id, "enableGTKAppId", BOOL, false, aliases: %w[enable-gtk-app-id]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "AppConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
