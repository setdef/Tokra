# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Base class for Tokra plugins.
  #
  # Mirrors Tauri's Plugin trait, providing lifecycle hooks for desktop
  # application integration.
  #
  # == Implementing a Plugin
  #
  # Subclass this and override the lifecycle methods:
  #
  #   class MyPlugin < Tokra::Plugin
  #     def name
  #       "my_plugin"
  #     end
  #
  #     def initialize(app, config = {})
  #       # Setup logic
  #     end
  #
  #     def on_event(app, event)
  #       # Handle run loop events
  #     end
  #   end
  #
  class Plugin
    # Returns the unique plugin identifier.
    def name
      raise NotImplementedError
    end

    # Initializes the plugin with app handle and configuration.
    #
    # Subclasses should call +super+ to store the app handle and config,
    # then perform their own setup.
    def initialize(app, config = {})
      @app = app
      @config = config
    end

    protected

    # The application handle. Available to subclasses.
    attr_reader :app

    # The plugin configuration hash. Available to subclasses.
    attr_reader :config

    # Called with the app handle for every run loop event.
    #
    # Override in subclasses to handle events. Mirrors the Plugin trait's
    # <tt>on_event(&mut self, app, event)</tt> (plugin.rs).
    # Returns +nil+ by default.
    public def on_event(app, event)
      nil
    end

    # Called when the webview navigates to a URL.
    #
    # Return +true+ to allow navigation, +false+ to block it.
    # Returns +true+ by default (allows all navigation).
    #
    # *Warning*: Returning +false+ blocks ALL navigation, which will
    # likely break your application. Only return +false+ for specific
    # URLs you want to prevent.
    public def on_navigation(webview, url)
      true
    end

    # Called to handle IPC invoke commands.
    #
    # Return +true+ if this plugin handled the command, +false+ otherwise.
    # When +false+, the invoke is passed to the next handler in the chain.
    #
    # *Note*: Returning +false+ passes the invoke to subsequent handlers.
    # If no handler returns +true+, the invoke will remain unhandled.
    public def extend_api(invoke)
      false
    end

    # Returns JavaScript to inject at document start.
    #
    # Override this to inject custom JavaScript into the webview.
    # Returns +nil+ by default (no script injection).
    public def initialization_script
      nil
    end

    # Called when a window is created.
    #
    # Override this to perform window-specific setup. Named without an
    # +on_+ prefix to mirror the Plugin trait's +window_created+
    # (plugin.rs).
    # Returns +nil+ by default (no-op).
    public def window_created(window)
      nil
    end

    # Called when a webview is created.
    #
    # Override this to perform webview-specific setup. Named without an
    # +on_+ prefix to mirror the Plugin trait's +webview_created+
    # (plugin.rs).
    # Returns +nil+ by default (no-op).
    public def webview_created(webview)
      nil
    end

    # Called when the webview finishes loading a page.
    #
    # Override this to perform post-load setup or analytics.
    # Returns +nil+ by default (no-op).
    public def on_page_load(webview, payload)
      nil
    end
  end

  # SPDX-SnippetBegin
  # SPDX-License-Identifier: Apache-2.0 OR MIT
  # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
  # SPDX-SnippetComment: PluginStore adapted from tauri/crates/tauri/src/plugin.rs

  # Routes IPC commands to registered plugins by name.
  #
  # A Tokra app hosts many plugins, each owning its own IPC commands.
  # Dispatching every command to every plugin would be slow, and one
  # plugin could shadow another's commands.
  #
  # This store keeps one plugin per name and routes each
  # <tt>plugin:NAME|command</tt> invoke to exactly one extend_api hook.
  # Mirrors Tauri's PluginStore (plugin.rs).
  #
  # === Example
  #
  #   store = Tokra::PluginStore.new
  #   store.register(MyPlugin.new(handle))
  #   store.extend_api("my-plugin", invoke)  #=> true when handled
  #
  class PluginStore
    # Creates an empty store.
    def initialize
      @store = []
    end

    # Adds a plugin to the store, replacing any same-named plugin.
    #
    # Returns +true+ if an existing plugin was replaced, +false+ otherwise.
    def register(plugin)
      length_before = @store.length
      @store.reject! { |p| p.name == plugin.name }
      @store.push(plugin)
      length_before != @store.length - 1
    end

    # Removes the plugin with the given name from the store.
    #
    # Returns +true+ if a plugin was removed, +false+ otherwise.
    def unregister(name)
      length_before = @store.length
      @store.reject! { |p| p.name == name }
      length_before != @store.length
    end

    # Routes an invoke to the named plugin's extend_api hook.
    #
    # Returns whether the invoke was handled. The invoke is not handled
    # when the plugin exists *and* the command does not. When no plugin
    # has the given name, the invoke is rejected and +true+ is returned,
    # matching Tauri's PluginStore#extend_api.
    def extend_api(name, invoke)
      plugin = @store.find { |p| p.name == name }
      return plugin.extend_api(invoke) if plugin

      invoke.reject("plugin #{name} not found")
      true
    end

    # Dispatches a run event to every registered plugin.
    #
    # Plugins like the clipboard release native resources on
    # RunEvent::Exit; without this fan-out those hooks never fire.
    # Mirrors Tauri's PluginStore#on_event (plugin.rs).
    def on_event(app, event)
      @store.each { |plugin| plugin.on_event(app, event) }
    end
  end

  # SPDX-SnippetEnd
end
