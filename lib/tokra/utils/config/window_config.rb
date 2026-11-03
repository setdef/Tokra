# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WindowConfig adapted from tauri-utils src/config.rs:1636-2063
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # One window your app opens, as the config describes it.
      #
      # Most apps open the same windows every time, with the same size,
      # title, and page. Writing them in code buries a design decision in
      # setup. The config lists them instead, in <tt>app.windows</tt>, and
      # each entry is one of these.
      #
      # Every key Tauri's <tt>WindowConfig</tt> has is here, with its
      # kebab-case alias, its default, and serde's refusal of a key it does
      # not know. A key reads in camelCase (<tt>alwaysOnTop</tt>) or its
      # alias (<tt>always-on-top</tt>), and each member is its snake_case
      # name. The default title is "Tokra App", as Tauri's is "Tauri App"
      # (ADR 014 §4).
      #
      # Some keys drive a part of Tokra that does not exist yet; they are
      # read and checked, and acted on when that part lands (plan 054's
      # inventory names each).
      #
      # Mirrors Tauri's <tt>WindowConfig</tt> (config.rs:1636-2063).
      #
      # === Examples
      #
      #   # "app": { "windows": [{ "label": "main", "title": "Notes", "width": 1024 }] }
      #   window = Tokra.generate_context.config.app.windows.first
      #   window.title   #=> "Notes"
      #   window.width   #=> 1024.0
      #   window.height  #=> 600.0
      #
      #   Tokra::Utils::Config::WindowConfig.new(label: "settings").create  #=> true
      class WindowConfig < Data.define(
        :label, :create, :url, :user_agent, :drag_drop_enabled, :center, :x, :y, :width, :height, :min_width,
        :min_height, :max_width, :max_height, :prevent_overflow, :resizable, :maximizable, :minimizable, :closable,
        :title, :fullscreen, :focus, :focusable, :transparent, :maximized, :visible, :decorations, :always_on_bottom,
        :always_on_top, :visible_on_all_workspaces, :content_protected, :skip_taskbar, :window_classname, :theme,
        :title_bar_style, :traffic_light_position, :hidden_title, :accept_first_mouse, :tabbing_identifier,
        :additional_browser_args, :shadow, :window_effects, :incognito, :parent, :proxy_url, :zoom_hotkeys_enabled,
        :browser_extensions_enabled, :use_https_scheme, :devtools, :background_color, :background_throttling,
        :javascript_disabled, :allow_link_preview, :disable_input_accessory_view, :data_directory,
        :data_store_identifier, :scroll_bar_style
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        BOOL = -> (raw) { Ipc::Serde.boolean(raw) } # :nodoc:
        F64 = -> (raw) { Ipc::Serde.f64(raw) } # :nodoc:
        # A Rust <tt>[u8; 16]</tt>.
        BYTES16 = lambda do |raw|
          Ipc::Serde.tuple(raw, 16, expecting: "an array of length 16") do |_index, byte|
            Ipc::CommandItem.integer(byte, "u8")
          end
        end # :nodoc:
        private_constant :STRING, :BOOL, :F64, :BYTES16

        # The fields in config.rs's order, which serde's unknown-field
        # error lists them in.
        FIELDS = [
          Field.defaulted(:label, "label", STRING, "main"),
          Field.defaulted(:create, "create", BOOL, true),
          Field.defaulted(:url, "url", -> (raw) { WebviewUrl.deserialize(raw) }, WebviewUrl::App.new(path: "index.html")),
          Field.option(:user_agent, "userAgent", STRING, aliases: %w[user-agent]),
          Field.defaulted(:drag_drop_enabled, "dragDropEnabled", BOOL, true, aliases: %w[drag-drop-enabled]),
          Field.defaulted(:center, "center", BOOL, false),
          Field.option(:x, "x", F64),
          Field.option(:y, "y", F64),
          Field.defaulted(:width, "width", F64, 800.0),
          Field.defaulted(:height, "height", F64, 600.0),
          Field.option(:min_width, "minWidth", F64, aliases: %w[min-width]),
          Field.option(:min_height, "minHeight", F64, aliases: %w[min-height]),
          Field.option(:max_width, "maxWidth", F64, aliases: %w[max-width]),
          Field.option(:max_height, "maxHeight", F64, aliases: %w[max-height]),
          Field.option(:prevent_overflow, "preventOverflow", -> (raw) { PreventOverflowConfig.deserialize(raw) },
            aliases: %w[prevent-overflow]),
          Field.defaulted(:resizable, "resizable", BOOL, true),
          Field.defaulted(:maximizable, "maximizable", BOOL, true),
          Field.defaulted(:minimizable, "minimizable", BOOL, true),
          Field.defaulted(:closable, "closable", BOOL, true),
          Field.defaulted(:title, "title", STRING, "Tokra App"),
          Field.defaulted(:fullscreen, "fullscreen", BOOL, false),
          Field.defaulted(:focus, "focus", BOOL, true),
          Field.defaulted(:focusable, "focusable", BOOL, true),
          Field.defaulted(:transparent, "transparent", BOOL, false),
          Field.defaulted(:maximized, "maximized", BOOL, false),
          Field.defaulted(:visible, "visible", BOOL, true),
          Field.defaulted(:decorations, "decorations", BOOL, true),
          Field.defaulted(:always_on_bottom, "alwaysOnBottom", BOOL, false, aliases: %w[always-on-bottom]),
          Field.defaulted(:always_on_top, "alwaysOnTop", BOOL, false, aliases: %w[always-on-top]),
          Field.defaulted(:visible_on_all_workspaces, "visibleOnAllWorkspaces", BOOL, false,
            aliases: %w[visible-on-all-workspaces]),
          Field.defaulted(:content_protected, "contentProtected", BOOL, false, aliases: %w[content-protected]),
          Field.defaulted(:skip_taskbar, "skipTaskbar", BOOL, false, aliases: %w[skip-taskbar]),
          Field.option(:window_classname, "windowClassname", STRING),
          Field.option(:theme, "theme", -> (raw) { Theme.deserialize(raw) }),
          Field.defaulted(:title_bar_style, "titleBarStyle", -> (raw) { TitleBarStyle.deserialize(raw) },
            TitleBarStyle::Visible, aliases: %w[title-bar-style]),
          Field.defaulted(:traffic_light_position, "trafficLightPosition", -> (raw) { LogicalPosition.deserialize(raw) },
            nil, aliases: %w[traffic-light-position], option: true),
          Field.defaulted(:hidden_title, "hiddenTitle", BOOL, false, aliases: %w[hidden-title]),
          Field.defaulted(:accept_first_mouse, "acceptFirstMouse", BOOL, false, aliases: %w[accept-first-mouse]),
          Field.defaulted(:tabbing_identifier, "tabbingIdentifier", STRING, nil, aliases: %w[tabbing-identifier],
            option: true),
          Field.defaulted(:additional_browser_args, "additionalBrowserArgs", STRING, nil,
            aliases: %w[additional-browser-args], option: true),
          Field.defaulted(:shadow, "shadow", BOOL, true),
          Field.defaulted(:window_effects, "windowEffects", -> (raw) { WindowEffectsConfig.deserialize(raw) }, nil,
            aliases: %w[window-effects], option: true),
          Field.defaulted(:incognito, "incognito", BOOL, false),
          Field.option(:parent, "parent", STRING),
          Field.option(:proxy_url, "proxyUrl", -> (raw) { Utils::Config.url(raw) }, aliases: %w[proxy-url]),
          Field.defaulted(:zoom_hotkeys_enabled, "zoomHotkeysEnabled", BOOL, false, aliases: %w[zoom-hotkeys-enabled]),
          Field.defaulted(:browser_extensions_enabled, "browserExtensionsEnabled", BOOL, false,
            aliases: %w[browser-extensions-enabled]),
          Field.defaulted(:use_https_scheme, "useHttpsScheme", BOOL, false, aliases: %w[use-https-scheme]),
          Field.option(:devtools, "devtools", BOOL),
          Field.option(:background_color, "backgroundColor", -> (raw) { Color.deserialize(raw) },
            aliases: %w[background-color]),
          Field.defaulted(:background_throttling, "backgroundThrottling",
            -> (raw) { BackgroundThrottlingPolicy.deserialize(raw) }, nil, aliases: %w[background-throttling],
            option: true),
          Field.defaulted(:javascript_disabled, "javascriptDisabled", BOOL, false, aliases: %w[javascript-disabled]),
          Field.defaulted(:allow_link_preview, "allowLinkPreview", BOOL, true, aliases: %w[allow-link-preview]),
          Field.defaulted(:disable_input_accessory_view, "disableInputAccessoryView", BOOL, false,
            aliases: %w[disable-input-accessory-view disable_input_accessory_view]),
          Field.defaulted(:data_directory, "dataDirectory", -> (raw) { Utils::Config.path(raw) }, nil,
            aliases: %w[data-directory], option: true),
          Field.defaulted(:data_store_identifier, "dataStoreIdentifier", BYTES16, nil, aliases: %w[data-store-identifier],
            option: true),
          Field.defaulted(:scroll_bar_style, "scrollBarStyle", -> (raw) { ScrollBarStyle.deserialize(raw) },
            ScrollBarStyle::Default, aliases: %w[scroll-bar-style]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "WindowConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default, as <tt>WindowConfig::default()</tt> gives it.
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
