# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: App structure adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # The built Tokra application.
  #
  # Created by calling Builder#build. Provides access to the application
  # handle and runs the event loop.
  class App
    include Manager

    # The application handle, safe to pass between Ractors.
    attr_reader :handle

    # The application configuration.
    attr_reader :config

    # Default window configuration when not specified.
    DEFAULT_CONFIG = {
      title: "Tokra",
      width: 800.0,
      height: 600.0,
    }.freeze

    # Creates a new App from a configured Builder.
    #
    # This is called by Builder#build and should not be called directly.
    # +native:+ can be injected for testing with mock native components.
    def initialize(builder, native: Native) # :nodoc:
      @config = DEFAULT_CONFIG.dup
      config = Config.new(
        identifier: @config[:identifier]&.to_s,
        product_name: @config[:product_name]&.to_s,
        version: @config[:version]&.to_s
      )
      manager = AppManager.new(config:, webviews: {}, windows: {})
      @handle = AppHandle.new(manager, state_manager: builder.__send__(:state_manager))
      @builder = builder
      # Store class references to avoid dynamic constant lookups
      @event_loop_class = native.const_get(:EventLoop)
      @window_class = native.const_get(:Window)
      @webview_class = native.const_get(:WebView)
    end

    # Runs the application event loop.
    #
    # Creates the native window and webview, then runs the event loop.
    # The block receives (handle, event) for each runtime event.
    def run(&callback)
      # Call setup hook before anything else
      @builder.__send__(:setup_hook)&.call(self)

      # Create native components via injected factory
      event_loop = @event_loop_class.new
      proxy = event_loop.create_proxy

      native_window = @window_class.new(event_loop)
      native_window.set_title(@config[:title].to_s)
      native_window.set_size(@config[:width].to_f, @config[:height].to_f)

      # Wrap the native window and register in manager
      window = Window.new(label: "main", native: native_window, app_handle: @handle)
      @window = window
      @handle.windows["main"] = window

      # Create and wrap the webview, register in manager
      native_webview = @webview_class.new_with_protocol(native_window, proxy)
      webview = Webview.new(label: "main", native: native_webview, window:, app_handle: @handle)
      @webview = webview
      @handle.webviews["main"] = webview

      # Emit Ready event
      callback&.call(@handle, RunEvent::Ready.new)

      # Run the event loop, dispatching events
      event_loop.run(
        lambda { |event|
          dispatch_event(event, callback, native_window, proxy)
        }
      )

      # Emit Exit after loop ends
      callback&.call(@handle, RunEvent::Exit.new)
    end

    private def dispatch_event(event, callback, window, proxy)
      # Use is_a? instead of case/when to support mock event injection in tests
      if event.is_a?(Native::HttpRequestEvent)
        dispatch_http_request(event, proxy)
      elsif event.is_a?(Native::IpcEvent)
        dispatch_ipc(event)
      elsif event.is_a?(Native::PageLoadEvent)
        dispatch_page_load(event)
      elsif event.is_a?(Native::WindowCloseEvent)
        dispatch_window_event(window, WindowEvent::CloseRequested.new, callback)
      elsif event.is_a?(Native::DragDropEvent)
        dispatch_webview_event(event)
      end
    end

    private def dispatch_http_request(event, proxy)
      sync_protocols = @builder.__send__(:uri_scheme_protocols)
      async_protocols = @builder.__send__(:async_uri_scheme_protocols)

      # Try sync protocol first (for backwards compatibility)
      if sync_protocols && (handler = sync_protocols["tokra"])
        ctx = UriSchemeContext.new(app_handle: @handle, webview_label: "main")
        response = handler.call(ctx, event)
        header_pairs = response.headers.map { |k, v| [k.to_s, v.to_s] }
        proxy.respond(event.request_id, response.status, header_pairs, response.body)
      elsif async_protocols && (handler = async_protocols["tokra"])
        ctx = UriSchemeContext.new(app_handle: @handle, webview_label: "main")
        responder = UriSchemeResponder.new(port: proxy, request_id: event.request_id)
        handler.call(ctx, event, responder)
      end
    end

    private def dispatch_ipc(event)
      handler = @builder.__send__(:invoke_handler_hook)
      return unless handler

      parsed = JSON.parse(event.message)
      invoke = Invoke.new(
        command: parsed["cmd"] || "",
        payload: parsed,
        responder: nil,
        webview: @webview # steep:ignore ArgumentTypeMismatch
      )
      handler.call(invoke)
    end

    private def dispatch_page_load(event)
      hook = @builder.__send__(:on_page_load_hook)
      return unless hook

      payload = PageLoadPayload.new(url: event.url, started: event.started?)
      hook.call(nil, payload) # webview object not yet wired
    end

    private def dispatch_window_event(window, event, callback)
      # Notify window event listeners
      @builder.__send__(:window_event_listeners)&.each do |listener|
        listener.call(window, event)
      end

      # Also emit as RunEvent::WindowEvent
      callback&.call(@handle, RunEvent::WindowEvent.new(label: "main", event:))
    end

    private def dispatch_webview_event(native_event)
      listeners = @builder.__send__(:webview_event_listeners)
      return unless listeners&.any?

      # Convert Native::DragDropEvent to WebviewEvent::DragDrop
      # Paths come from Rust as strings, convert to Pathname per Tauri's PathBuf semantics
      drag_event = case native_event.event
      when "enter"
        paths = native_event.paths.map { |p| Pathname.new(p) }
        DragDropEvent::Enter.new(paths, PhysicalPosition.new(native_event.x, native_event.y))
      when "over"
        DragDropEvent::Over.new(PhysicalPosition.new(native_event.x, native_event.y))
      when "drop"
        paths = native_event.paths.map { |p| Pathname.new(p) }
        DragDropEvent::Drop.new(paths, PhysicalPosition.new(native_event.x, native_event.y))
      when "leave"
        DragDropEvent::Leave.new
      else
        return # Unknown event type, ignore
      end

      webview_event = WebviewEvent::DragDrop.new(drag_event)

      listeners.each do |listener|
        listener.call(nil, webview_event) # webview object not yet wired
      end
    end
  end
end

# SPDX-SnippetEnd
