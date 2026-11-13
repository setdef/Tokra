# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Builder, BuilderError, and their rustdoc adapted from
#                      tauri/crates/tauri/src/plugin.rs:181-756

module Tokra
  class Plugin
    # Raised when a Builder cannot build its plugin.
    #
    # Mirrors Tauri's <tt>plugin::BuilderError</tt> (plugin.rs:181-188).
    class BuilderError < Error
      # Raised for a plugin named +core+ or +tauri+, names Tauri keeps for
      # itself.
      #
      # Mirrors <tt>BuilderError::ReservedName</tt>, "plugin uses reserved
      # name: {0}" (plugin.rs:185-187, 190).
      #
      # === Example
      #
      #   Tokra::Plugin::Builder.new("core").build
      #   # raises Tokra::Plugin::BuilderError::ReservedName: plugin uses reserved name: core
      class ReservedName < BuilderError
        # The reserved name the plugin asked for.
        attr_reader :name

        # The error for +name+, a reserved plugin name.
        def initialize(name)
          @name = name
          super("plugin uses reserved name: #{name}")
        end
      end
    end

    # Builds a plugin from blocks, as Tauri's plugins are built.
    #
    # A plugin is mostly a list of answers: which commands it serves,
    # what script its pages run first, what it sets up when the app
    # starts, and what it does as windows, pages, and events come and go.
    # Writing a Plugin subclass for that means a class with a method per
    # answer and state to carry between them.
    #
    # This builder takes each answer as a block and builds a TauriPlugin
    # that calls them. Every block has Tauri's default, so give only the
    # ones you need. Register what #build returns with Tokra::Builder#plugin.
    #
    # Use it to write a plugin the way Tauri's own are written, and to
    # read its settings from the app config's +plugins+.
    #
    # == Conventions
    #
    # A plugin gem defines a function called +init+ that builds and
    # returns the plugin, as Tauri's crates do, so an app finds it at once.
    # When a plugin has options, a builder of its own whose +build+ calls
    # this one serves better.
    #
    # Each method stores its block, replacing an earlier one, and returns
    # the builder. A method that takes a block raises ArgumentError
    # without one. The blocks run on the main Ractor, in the plugin store,
    # and need not be Ractor-shareable (plan 064, decision 4).
    #
    # Mirrors Tauri's <tt>plugin::Builder</tt> (plugin.rs:192-756).
    #
    # === Examples
    #
    #   module Greeter
    #     def self.init
    #       Tokra::Plugin::Builder.new("greeter")
    #         .invoke_handler { |invoke|
    #           next false unless invoke.command == "greet"
    #
    #           invoke.resolve("Hello, #{invoke.payload['name']}!")
    #           true
    #         }
    #         .build
    #     end
    #   end
    #
    #   Tokra::Builder.default.plugin(Greeter.init).run(Tokra.generate_context)
    #
    #   # A plugin with options, built by a builder of its own:
    #   class Recorder
    #     def initialize
    #       @path = "recording.log"
    #     end
    #
    #     def path(path)
    #       @path = path
    #       self
    #     end
    #
    #     def build
    #       path = @path
    #       Tokra::Plugin::Builder.new("recorder")
    #         .setup { |app, _api| app.manage(File.open(path, "a")) }
    #         .build
    #     end
    #   end
    class Builder
      # The names a plugin may not take (plugin.rs:190).
      RESERVED_PLUGIN_NAMES = %w[core tauri].freeze

      # Rust's unit type, <tt>()</tt>, as a config type: the slice must be
      # null or absent, and the setup block gets +nil+. A plugin whose
      # Builder takes no <tt>config:</tt> reads its config this way, as a
      # Tauri plugin's config type defaults to <tt>()</tt> (plugin.rs:264).
      module Unit
        # +nil+ for null, or serde's "invalid type: ..., expected unit".
        def self.deserialize(value)
          Ipc::Serde.unit(value)
        end
      end

      # A builder for a plugin named +name+, the name in its
      # <tt>plugin:NAME|command</tt> invokes and its key in the app
      # config's +plugins+.
      #
      # [name] a String.
      # [config] what reads the plugin's config, Tauri's config type: any
      #          object whose <tt>deserialize(value)</tt> takes the JSON
      #          value and returns the config, raising
      #          Ipc::CommandItem::Mismatch with serde's words when it
      #          cannot. Unit by default (plan 064, decision 3).
      #
      # Mirrors Tauri's <tt>Builder::new</tt> (plugin.rs:278-294).
      #
      # === Example
      #
      #   Tokra::Plugin::Builder.new("example")
      def initialize(name, config: Unit)
        @name = name
        @config_type = config
        @invoke_handler = -> (_invoke) { false }
        @setup = nil
        @js_init_script = nil
        @on_navigation = -> (_webview, _url) { true }
        @on_page_load = -> (_webview, _payload) {}
        @on_window_ready = -> (_window) {}
        @on_webview_ready = -> (_webview) {}
        @on_event = -> (_app, _event) {}
        @on_drop = nil
      end

      # Defines the JS message handler callback: the block gets each
      # Ipc::Invoke for this plugin, its command bare, and returns whether
      # it handled it. An invoke it leaves rejects with "Command NAME not
      # found".
      #
      # Mirrors Tauri's <tt>Builder::invoke_handler</tt> (plugin.rs:296-326).
      #
      # === Example
      #
      #   builder.invoke_handler { |invoke|
      #     next false unless invoke.command == "foobar"
      #
      #     invoke.resolve(nil)
      #     true
      #   }
      def invoke_handler(&block)
        @invoke_handler = required(block, __method__)
        self
      end

      # Sets the provided JavaScript to be run after the global object has
      # been created, but before the HTML document has been parsed and
      # before any other script included by the HTML document is run.
      #
      # The script is wrapped into its own context with
      # <tt>(function () { /* your script here */ })();</tt>, so global
      # variables must be assigned to +window+ instead of implicitly
      # declared.
      #
      # Note that calling this method multiple times overrides previous
      # values, #js_init_script_on_all_frames's included.
      #
      # This is executed only on the main frame. If you want it to run in
      # every frame, use #js_init_script_on_all_frames instead. On Windows
      # scripts are always added to subframes.
      #
      # Mirrors Tauri's <tt>Builder::js_init_script</tt> (plugin.rs:328-376).
      #
      # === Example
      #
      #   builder.js_init_script(<<~JS)
      #     if (window.location.origin === 'tokra://localhost') {
      #       window.__MY_CUSTOM_PROPERTY__ = { foo: 'bar' };
      #     }
      #   JS
      def js_init_script(js_init_script)
        @js_init_script = [js_init_script.to_s.dup.freeze, true].freeze
        self
      end

      # Sets the provided JavaScript to be run after the global object has
      # been created, but before the HTML document has been parsed and
      # before any other script included by the HTML document is run.
      #
      # Since it runs on all top-level document and child frame page
      # navigations, it's recommended to check the +window.location+ to
      # guard your script from running on unexpected origins.
      #
      # Note that calling this method multiple times overrides previous
      # values, #js_init_script's included.
      #
      # This is executed on all frames, main frame and also sub frames. If
      # you only want to run it in the main frame, use #js_init_script
      # instead.
      #
      # Mirrors Tauri's <tt>Builder::js_init_script_on_all_frames</tt>
      # (plugin.rs:378-405).
      #
      # === Example
      #
      #   builder.js_init_script_on_all_frames("window.__IN_APP__ = true")
      def js_init_script_on_all_frames(js_init_script)
        @js_init_script = [js_init_script.to_s.dup.freeze, false].freeze
        self
      end

      # Defines a block that runs when the plugin is registered, with the
      # AppHandle and a PluginApi holding the plugin's config. It runs
      # once. Raise to fail the registration, which the app reports as
      # Error::PluginInitialization.
      #
      # Mirrors Tauri's <tt>Builder::setup</tt> (plugin.rs:407-439).
      #
      # === Example
      #
      #   builder.setup { |app, _api| app.manage(PluginState.new) }
      def setup(&block)
        @setup = required(block, __method__)
        self
      end

      # Callback invoked when the webview tries to navigate to a URL, with
      # the Webview and the Ferro::Url::Url. Returning +false+ cancels the
      # navigation.
      #
      # *Not called yet*: Tokra's webview registers no navigation handler
      # until plan 052e-4 (plan 064, decision 9).
      #
      # Mirrors Tauri's <tt>Builder::on_navigation</tt> (plugin.rs:441-464).
      #
      # === Example
      #
      #   builder.on_navigation { |_webview, url| url.scheme == "tokra" }
      def on_navigation(&block)
        @on_navigation = required(block, __method__)
        self
      end

      # Callback invoked when the webview performs a navigation to a page,
      # with the Webview and a PageLoadPayload.
      #
      # Mirrors Tauri's <tt>Builder::on_page_load</tt> (plugin.rs:466-488).
      #
      # === Example
      #
      #   builder.on_page_load { |webview, payload|
      #     puts "#{payload.url} in webview #{webview.label}" if payload.finished?
      #   }
      def on_page_load(&block)
        @on_page_load = required(block, __method__)
        self
      end

      # Callback invoked when the window is created, with the Window.
      #
      # Mirrors Tauri's <tt>Builder::on_window_ready</tt> (plugin.rs:490-512).
      #
      # === Example
      #
      #   builder.on_window_ready { |window| puts "created window #{window.label}" }
      def on_window_ready(&block)
        @on_window_ready = required(block, __method__)
        self
      end

      # Callback invoked when the webview is created, with the Webview.
      #
      # Mirrors Tauri's <tt>Builder::on_webview_ready</tt> (plugin.rs:514-536).
      #
      # === Example
      #
      #   builder.on_webview_ready { |webview| puts "created webview #{webview.label}" }
      def on_webview_ready(&block)
        @on_webview_ready = required(block, __method__)
        self
      end

      # Callback invoked when the event loop receives a new event, with
      # the AppHandle and the RunEvent.
      #
      # Mirrors Tauri's <tt>Builder::on_event</tt> (plugin.rs:538-568).
      #
      # === Example
      #
      #   builder.on_event { |_app, event|
      #     # Keeps the app running in the background with no windows open.
      #     event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested)
      #   }
      def on_event(&block)
        @on_event = required(block, __method__)
        self
      end

      # Callback invoked when the plugin is dropped, with the AppHandle:
      # when AppHandle#remove_plugin removes it, when a plugin of the same
      # name replaces it, or when its setup fails. It runs once, and only
      # if the plugin was initialized (Plugin#drop).
      #
      # Mirrors Tauri's <tt>Builder::on_drop</tt> (plugin.rs:570-593).
      #
      # === Example
      #
      #   builder.on_drop { |_app| puts "plugin has been dropped and is no longer running" }
      def on_drop(&block)
        @on_drop = required(block, __method__)
        self
      end

      # Builds the TauriPlugin, or raises BuilderError::ReservedName for a
      # name in RESERVED_PLUGIN_NAMES.
      #
      # Mirrors Tauri's <tt>Builder::try_build</tt> (plugin.rs:726-746).
      #
      # === Example
      #
      #   plugin = Tokra::Plugin::Builder.new("example").try_build
      def try_build
        raise BuilderError::ReservedName, @name if RESERVED_PLUGIN_NAMES.include?(@name)

        TauriPlugin.new(name: @name, config_type: @config_type, invoke_handler: @invoke_handler, setup: @setup,
          js_init_script: @js_init_script, on_navigation: @on_navigation, on_page_load: @on_page_load,
          on_window_ready: @on_window_ready, on_webview_ready: @on_webview_ready, on_event: @on_event,
          on_drop: @on_drop)
      end

      # Builds the TauriPlugin, as #try_build does. Tauri's panics where
      # #try_build returns an error; in Ruby both raise it.
      #
      # Mirrors Tauri's <tt>Builder::build</tt> (plugin.rs:748-755).
      #
      # === Example
      #
      #   Tokra::Builder.default.plugin(Tokra::Plugin::Builder.new("example").build)
      def build
        try_build
      end

      # +block+, or ArgumentError naming +method+ when there is none.
      private def required(block, method)
        raise ArgumentError, "#{method} needs a block" unless block

        block
      end
    end
  end
end

# SPDX-SnippetEnd
