# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Builder pattern adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Fluent Builder for configuring Tokra desktop applications.
  #
  # Mirrors Tauri's Builder API structure but uses Ruby idioms.
  class Builder
    # Creates a new Builder with default configuration.
    #
    # This mirrors Tauri's +Builder::default()+ which implements the Default trait.
    def self.default
      new
    end

    # Initializes a new Builder with empty collections.
    def initialize
      @uri_scheme_protocols = {}
      @async_uri_scheme_protocols = {}
      @window_event_listeners = []
      @webview_event_listeners = []
      @state_manager = StateManager.new
    end

    # Registers managed state accessible via AppHandle.
    #
    # State is keyed by class. One instance per class.
    def manage(state)
      @state_manager.set(state)
      self
    end

    # Defines the JS message handler callback.
    #
    # Accepts a block that receives the invoke object containing command info.
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def invoke_handler(&block)
      require_shareable!(block, "invoke_handler")
      @invoke_handler_hook = block
      self
    end

    # Registers a URI scheme protocol available to all webviews.
    #
    # The block receives (ctx, request) and should return a response.
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def register_uri_scheme_protocol(uri_scheme, &handler)
      require_shareable!(handler, "register_uri_scheme_protocol")
      @uri_scheme_protocols[uri_scheme] = handler
      self
    end

    # Registers an async URI scheme protocol available to all webviews.
    #
    # The block receives (ctx, request, responder) and must call
    # +responder.respond(response)+ when complete.
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def register_asynchronous_uri_scheme_protocol(uri_scheme, &handler)
      require_shareable!(handler, "register_asynchronous_uri_scheme_protocol")
      @async_uri_scheme_protocols[uri_scheme] = handler
      self
    end

    # Defines the setup hook.
    #
    # The block receives the App instance after build.
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def setup(&block)
      require_shareable!(block, "setup")
      @setup_hook = block
      self
    end

    # Defines the page load hook.
    #
    # The block receives (webview, payload).
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def on_page_load(&block)
      require_shareable!(block, "on_page_load")
      @on_page_load_hook = block
      self
    end

    # Registers a window event handler for all windows.
    #
    # The block receives (window, event).
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def on_window_event(&block)
      require_shareable!(block, "on_window_event")
      @window_event_listeners << block
      self
    end

    # Registers a webview event handler for all webviews.
    #
    # The block receives (webview, webview_event).
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def on_webview_event(&block)
      require_shareable!(block, "on_webview_event")
      @webview_event_listeners << block
      self
    end

    # Builds the configured application.
    #
    # Returns an App instance ready to run.
    # +native:+ can be injected for testing with mock native components.
    def build(native: Native)
      App.new(self, native:)
    end

    # Builds and runs the application.
    #
    # This is a convenience for Builder#build followed by App#run.
    # Accepts an optional block for runtime events.
    # +native:+ can be injected for testing with mock native components.
    def run(native: Native, &callback)
      app = build(native:)
      if callback
        app.run(&callback)
      else
        app.run
      end
    end

    # Consider these "friendly" -- public to Tokra, private to app devs.
    attr_reader :state_manager, :invoke_handler_hook, :uri_scheme_protocols, # :nodoc:
      :async_uri_scheme_protocols, :setup_hook, :on_page_load_hook,
      :window_event_listeners, :webview_event_listeners

    private def require_shareable!(block, method_name)
      return if Ractor.shareable?(block)

      raise Error, "#{method_name} block must be Ractor-shareable (use Ractor.shareable_proc)"
    end
  end
end

# SPDX-SnippetEnd
