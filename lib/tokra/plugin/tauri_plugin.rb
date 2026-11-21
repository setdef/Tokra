# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TauriPlugin adapted from tauri/crates/tauri/src/plugin.rs:758-853

module Tokra
  class Plugin
    # The plugin a Plugin::Builder builds.
    #
    # A plugin built from blocks still has to answer every hook the app
    # calls, and has to read its config and run its setup once, when the
    # app registers it.
    #
    # This class answers each hook with the block the builder was given,
    # or Tauri's default. Make one with Plugin::Builder#build and register
    # it with Tokra::Builder#plugin or AppHandle#plugin.
    #
    # Mirrors Tauri's <tt>TauriPlugin</tt> (plugin.rs:758-853), which only
    # the builder constructs.
    #
    # === Example
    #
    #   plugin = Tokra::Plugin::Builder.new("example").js_init_script("window.example = true").build
    #   plugin.name  #=> "example"
    class TauriPlugin < Plugin
      # Made by Plugin::Builder#try_build from the builder's blocks.
      def initialize(name:, config_type:, invoke_handler:, setup:, js_init_script:, on_navigation:, on_page_load:, # :nodoc:
        on_window_ready:, on_webview_ready:, on_event:, on_drop:
      )
        super()
        @name = name
        @config_type = config_type
        @invoke_handler = invoke_handler
        @setup = setup
        @js_init_script = js_init_script
        @on_navigation = on_navigation
        @on_page_load = on_page_load
        @on_window_ready = on_window_ready
        @on_webview_ready = on_webview_ready
        @on_event = on_event
        @on_drop = on_drop
      end

      # The plugin's name (plugin.rs:783-785).
      def name
        @name
      end

      # Keeps +app+, then runs the setup block once, if there is one, with
      # +app+ and a PluginApi whose config is +config+ read by the
      # builder's config type. A config the type cannot read raises
      # Tokra::Error, "Error deserializing 'plugins.NAME' within your Tokra
      # configuration: ERROR", Tauri's message with the brand renamed
      # (doc/contributors/design/config.md, "File names"); a plugin with no
      # setup block never reads its config.
      # Returns +nil+.
      #
      # Mirrors <tt>TauriPlugin::initialize</tt> (plugin.rs:787-817). Its
      # URI scheme protocols wait for the native layer (plan 064, decision
      # 10).
      def initialize_plugin(app, config)
        super
        setup = @setup
        return nil unless setup

        @setup = nil
        setup.call(app, PluginApi.new(app:, config: read_config(config), name: @name))
        nil
      end

      # The builder's script, or +nil+ (plugin.rs:819-824).
      def initialization_script
        @js_init_script&.first
      end

      # The builder's script with its frames, or +nil+ (plugin.rs:826-828).
      def initialization_script_2
        @js_init_script
      end

      # Calls the builder's #on_window_ready block (plugin.rs:830-832).
      def window_created(window)
        @on_window_ready.call(window)
        nil
      end

      # Calls the builder's #on_webview_ready block (plugin.rs:834-836).
      def webview_created(webview)
        @on_webview_ready.call(webview)
        nil
      end

      # Answers the builder's #on_navigation block (plugin.rs:838-840).
      def on_navigation(webview, url)
        @on_navigation.call(webview, url)
      end

      # Calls the builder's #on_page_load block (plugin.rs:842-844).
      def on_page_load(webview, payload)
        @on_page_load.call(webview, payload)
        nil
      end

      # Calls the builder's #on_event block (plugin.rs:846-848).
      def on_event(app, event)
        @on_event.call(app, event)
        nil
      end

      # Answers the builder's #invoke_handler block (plugin.rs:850-852).
      def extend_api(invoke)
        @invoke_handler.call(invoke)
      end

      # Runs the builder's #on_drop block with the app, once, and only if
      # the plugin was initialized; returns +nil+. Tauri's +Drop+ takes
      # the block, so a second drop does nothing (plugin.rs:774-780).
      def drop
        on_drop = @on_drop
        @on_drop = nil
        app = @app
        on_drop.call(app) if on_drop && app
        nil
      end

      # +config+ read by the builder's config type, or the error Tauri
      # reports for a config it cannot read (plugin.rs:800-805).
      private def read_config(config)
        @config_type.deserialize(config)
      rescue Ipc::CommandItem::Mismatch => e
        raise Error, "Error deserializing 'plugins.#{@name}' within your Tokra configuration: #{e.message}"
      end
    end
  end
end

# SPDX-SnippetEnd
