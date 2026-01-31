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
      @window_event_listeners = []
    end

    # Returns the invoke handler for App to call.
    attr_reader :invoke_handler_hook

    # Defines the JS message handler callback.
    #
    # Accepts a block that receives the invoke object containing command info.
    # Returns +self+ for fluent chaining.
    def invoke_handler(&block)
      @invoke_handler_hook = block
      self
    end

    # Returns the registered URI scheme protocols.
    attr_reader :uri_scheme_protocols

    # Registers a URI scheme protocol available to all webviews.
    #
    # The block receives (ctx, request) and should return a response.
    # Returns +self+ for fluent chaining.
    def register_uri_scheme_protocol(uri_scheme, &handler)
      @uri_scheme_protocols[uri_scheme] = handler
      self
    end

    # Defines the setup hook.
    #
    # The block receives the App instance after build.
    # Returns +self+ for fluent chaining.
    # Returns the setup hook for App to call.
    attr_reader :setup_hook

    # Defines the setup hook.
    #
    # The block receives the App instance after build.
    # Returns +self+ for fluent chaining.
    def setup(&block)
      @setup_hook = block
      self
    end

    # Returns the page load hook for App to call.
    attr_reader :on_page_load_hook

    # Defines the page load hook.
    #
    # The block receives (webview, payload).
    # Returns +self+ for fluent chaining.
    def on_page_load(&block)
      @on_page_load_hook = block
      self
    end

    # Returns the list of window event listeners.
    attr_reader :window_event_listeners

    # Registers a window event handler for all windows.
    #
    # The block receives (window, event).
    # Returns +self+ for fluent chaining.
    def on_window_event(&block)
      @window_event_listeners << block
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
  end
end

# SPDX-SnippetEnd
