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
  #     def on_event(event)
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

    # Called when an event is dispatched to the plugin.
    #
    # Override in subclasses to handle events.
    # Returns +nil+ by default.
    public def on_event(event)
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
    # Override this to perform window-specific setup.
    # Returns +nil+ by default (no-op).
    public def on_window_created(window)
      nil
    end

    # Called when a webview is created.
    #
    # Override this to perform webview-specific setup.
    # Returns +nil+ by default (no-op).
    public def on_webview_created(webview)
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
end
