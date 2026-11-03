# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TrayIconConfig adapted from tauri-utils src/config.rs:2802-2840
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The tray icon your app shows, as the config describes it.
      #
      # An app that lives in the menu bar or the system tray shows one
      # icon there from the start. The config names its image and how it
      # behaves, so the app builds it before your setup code runs.
      #
      # Tokra reads it now and builds the tray from it in plan 054's third
      # phase (plan 049, part B).
      #
      # Mirrors Tauri's <tt>TrayIconConfig</tt> (config.rs:2802-2840).
      #
      # === Example
      #
      #   # "trayIcon": { "iconPath": "icons/tray.png", "iconAsTemplate": true }
      #   tray = Tokra.generate_context.config.app.tray_icon
      #   tray.icon_path         #=> #<Pathname:icons/tray.png>
      #   tray.icon_as_template  #=> true
      class TrayIconConfig < Data.define(
        :id, :icon_path, :icon_as_template, :menu_on_left_click, :show_menu_on_left_click, :title, :tooltip
      )
        BOOL = -> (raw) { Ipc::Serde.boolean(raw) } # :nodoc:
        private_constant :BOOL

        FIELDS = [
          Field.option(:id, "id", -> (raw) { Ipc::Serde.string(raw) }),
          Field.required(:icon_path, "iconPath", -> (raw) { Utils::Config.path(raw) }, aliases: %w[icon-path]),
          Field.defaulted(:icon_as_template, "iconAsTemplate", BOOL, false, aliases: %w[icon-as-template]),
          Field.defaulted(:menu_on_left_click, "menuOnLeftClick", BOOL, true, aliases: %w[menu-on-left-click]),
          Field.defaulted(:show_menu_on_left_click, "showMenuOnLeftClick", BOOL, true,
            aliases: %w[show-menu-on-left-click]),
          Field.option(:title, "title", -> (raw) { Ipc::Serde.string(raw) }),
          Field.option(:tooltip, "tooltip", -> (raw) { Ipc::Serde.string(raw) }),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "TrayIconConfig", FIELDS)) # steep:ignore InsufficientKeywordArguments
        end

        # Takes the members as keywords: +icon_path+, which Tauri requires,
        # and any of the rest, each one left out taking serde's default
        # (Rust's derived Default differs: it fills false where serde fills
        # true).
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
