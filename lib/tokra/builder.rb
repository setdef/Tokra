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
    # This mirrors Tauri's <tt>Builder::default()</tt> which implements the Default trait.
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
      @rack_app = nil
      @window_config = {}
      @with_global_tauri = false
    end

    # Sets the window title.
    #
    # Mirrors the <tt>.title(...)</tt> step in ADR 004's Builder API.
    #
    # === Example
    #
    #   Tokra::Builder.new.title("My App").run
    def title(title)
      @window_config[:title] = title
      self
    end

    # Sets the window size in logical pixels.
    #
    # Mirrors the <tt>.size(width, height)</tt> step in ADR 004's Builder API.
    #
    # === Example
    #
    #   Tokra::Builder.new.size(1024, 768).run
    def size(width, height)
      @window_config[:width] = width.to_f
      @window_config[:height] = height.to_f
      self
    end

    # Sets the Rack application served over the <tt>tokra://</tt> protocol.
    #
    # A Tokra window has no TCP server. Instead of pointing the WebView at
    # <tt>http://localhost:3000</tt>, the WebView loads <tt>tokra://localhost/</tt>
    # and the framework calls your Rack app in-process for each request.
    #
    # Pass any Rack application (Rails, Roda, Sinatra) and the built App
    # serves it, following redirects and forwarding cookies. Mirrors the
    # <tt>.app(MyRackApp)</tt> context step in ADR 004; the request/response
    # translation is handled by <tt>Rack::Handler::Tokra</tt>.
    #
    # === Example
    #
    #   Tokra::Builder.new
    #     .app(MyRodaApp.freeze.app)
    #     .title("My App")
    #     .run
    def app(rack_app)
      # Defensive runtime check: the type contract says Rack app, but Ruby
      # callers can pass anything, so we validate for a clear error.
      unless rack_app.respond_to?(:call) # steep:ignore NoMethod
        raise Error, "app must be a Rack application (respond to #call)"
      end

      @rack_app = rack_app
      self
    end

    # Injects the @tauri-apps/api bundle as <tt>window.__TAURI__</tt>.
    #
    # A page with no frontend bundler cannot +import+ from
    # <tt>@tauri-apps/api</tt>. Tauri solves this with <tt>withGlobalTauri</tt>,
    # which injects the API's prebuilt IIFE as an initialization script, so the
    # page calls <tt>window.__TAURI__.core.invoke(...)</tt> directly.
    #
    # Set this to expose the whole vendored API the same way. It mirrors
    # <tt>app.withGlobalTauri</tt> in Tauri's configuration; Tokra gates it at
    # runtime rather than through build-time codegen.
    #
    # === Example
    #
    #   Tokra::Builder.new.with_global_tauri.app(MyRodaApp.freeze.app).run
    def with_global_tauri(enabled = true)
      @with_global_tauri = enabled
      self
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
    # <tt>native:</tt> can be injected for testing with mock native components.
    def build(native: Native)
      App.new(self, native:)
    end

    # Builds and runs the application.
    #
    # This is a convenience for Builder#build followed by App#run.
    # Accepts an optional block for runtime events.
    # <tt>native:</tt> can be injected for testing with mock native components.
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
      :window_event_listeners, :webview_event_listeners, :rack_app, :window_config

    # Whether the @tauri-apps/api bundle should be injected (friendly reader;
    # a predicate so it does not collide with the with_global_tauri setter).
    def with_global_tauri? # :nodoc:
      @with_global_tauri
    end

    private def require_shareable!(block, method_name)
      return if Ractor.shareable?(block)

      raise Error, "#{method_name} block must be Ractor-shareable (use Ractor.shareable_proc)"
    end
  end
end

# SPDX-SnippetEnd
