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
      @menu_event_listeners = []
      @tray_icon_event_listeners = []
      @menu_hook = nil
      @enable_macos_default_menu = true
      @state_manager = StateManager.new
      @rack_app = nil
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
    #     .run(Tokra.generate_context)
    def app(rack_app)
      # Defensive runtime check: the type contract says Rack app, but Ruby
      # callers can pass anything, so we validate for a clear error.
      unless rack_app.respond_to?(:call) # steep:ignore NoMethod
        raise Error, "app must be a Rack application (respond to #call)"
      end

      @rack_app = rack_app
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

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: The builder's menu adapted from tauri/crates/tauri/src/app.rs

    # Sets the app's menu: the block receives the AppHandle and returns a
    # Menu::Menu.
    #
    # App#run calls it once the event loop exists and before the setup
    # hook, and the menu becomes the app's, as AppHandle#set_menu would
    # make it (plan 042, decision 7). An error the block raises ends
    # App#run, as Tauri's Builder::build returns it.
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    #
    # Mirrors Tauri's Builder::menu (app.rs:1828-1834).
    #
    # === Example
    #
    #   Tokra::Builder.default.menu(Ractor.shareable_proc { |app| Tokra::Menu::Menu.default(app) })
    def menu(&block)
      require_shareable!(block, "menu")
      @menu_hook = block
      self
    end

    # Adds a block that hears each click on a menu item, with the
    # AppHandle and a Menu::MenuEvent, as AppHandle#on_menu_event adds one.
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    #
    # Mirrors Tauri's Builder::on_menu_event (app.rs:1836-1857).
    def on_menu_event(&block)
      require_shareable!(block, "on_menu_event")
      @menu_event_listeners << block
      self
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: on_tray_icon_event adapted from tauri/crates/tauri/src/app.rs

    # Adds a block that hears each event of any tray icon, with the
    # AppHandle and a Tray::TrayIconEvent, as AppHandle#on_tray_icon_event
    # adds one. The block must be Ractor-shareable (use
    # +Ractor.shareable_proc+).
    #
    # Mirrors Tauri's Builder::on_tray_icon_event (app.rs:1859-1879).
    #
    # === Example
    #
    #   Tokra::Builder.default.on_tray_icon_event(&Ractor.shareable_proc { |app, event| puts event.id })
    def on_tray_icon_event(&block)
      require_shareable!(block, "on_tray_icon_event")
      @tray_icon_event_listeners << block
      self
    end

    # SPDX-SnippetEnd

    # Whether an app that sets no #menu gets Menu::Menu.default on macOS,
    # as it does unless told otherwise. Elsewhere such an app has no menu.
    #
    # Mirrors Tauri's Builder::enable_macos_default_menu
    # (app.rs:1859-1893, 2094-2100).
    #
    # === Example
    #
    #   Tokra::Builder.default.enable_macos_default_menu(false)
    def enable_macos_default_menu(enable)
      @enable_macos_default_menu = enable
      self
    end

    # SPDX-SnippetEnd

    # Defines the page load hook.
    #
    # The block receives the Tokra::Webview that started or finished
    # loading a page and a PageLoadPayload, before any plugin's
    # Plugin#on_page_load, as Tauri's on_page_load does
    # (manager/webview.rs:282-300).
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    #
    # === Example
    #
    #   builder.on_page_load(&Ractor.shareable_proc { |webview, payload|
    #     puts "#{webview.label} loaded #{payload.url}" if payload.finished?
    #   })
    def on_page_load(&block)
      require_shareable!(block, "on_page_load")
      @on_page_load_hook = block
      self
    end

    # Registers a window event handler for all windows.
    #
    # The block receives the Tokra::Window and each WindowEvent it gets,
    # after the App#run block and plugins have heard it and the page has
    # heard its <tt>tauri://</tt> event, except
    # WindowEvent::CloseRequested, which it hears before them. Blocks run
    # in the order they were added, before the window's own
    # Window#on_window_event blocks. Mirrors Tauri's
    # Builder::on_window_event (app.rs; manager/window.rs:93-100).
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def on_window_event(&block)
      require_shareable!(block, "on_window_event")
      @window_event_listeners << block
      self
    end

    # Registers a webview event handler for all webviews.
    #
    # The block receives (webview, webview_event). Tokra's webview fills its
    # window, and Tauri reports such a webview's drops as the window's
    # (WindowEvent::DragDrop), so no event reaches this block yet.
    # The block must be Ractor-shareable (use +Ractor.shareable_proc+).
    def on_webview_event(&block)
      require_shareable!(block, "on_webview_event")
      @webview_event_listeners << block
      self
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: build and run adapted from tauri/crates/tauri/src/app.rs:2094-2302

    # Builds the app from +context+, the Tokra::Context
    # Tokra.generate_context reads from your <tt>tokra.conf.json</tt>, and
    # answers an App ready to run. The app's config, package information,
    # and pattern are the context's, and App#run opens the windows the
    # config's <tt>app.windows</tt> lists.
    #
    # Raises TypeError unless +context+ is a Tokra::Context.
    #
    # <tt>native:</tt> can be injected for testing with mock native components.
    # A stand-in for Tokra::Native also defines its menu classes (+Menu+,
    # +Submenu+, +MenuItem+, +CheckMenuItem+, +PredefinedMenuItem+,
    # +IconMenuItem+, +MenuIcon+); the real ones need no window, so a
    # stand-in can name them.
    #
    # Mirrors Tauri's <tt>Builder::build</tt> (app.rs:2094).
    #
    # === Example
    #
    #   app = Tokra::Builder.default.build(Tokra.generate_context)
    #   app.run
    def build(context, native: Native)
      App.new(self, context, native:)
    end

    # Builds the app from +context+, as #build does, and runs it.
    #
    # Accepts an optional block for runtime events, which App#run hands
    # each RunEvent. Tauri's <tt>Builder::run</tt> takes none; this block
    # predates the config and stays (plan 054, decision 12).
    # <tt>native:</tt> can be injected for testing with mock native components.
    #
    # Mirrors Tauri's <tt>Builder::run</tt> (app.rs:2298-2302).
    #
    # === Example
    #
    #   Tokra::Builder.default
    #     .setup(&Ractor.shareable_proc { |app| puts app.config.identifier })
    #     .run(Tokra.generate_context)
    def run(context, native: Native, &callback)
      app = build(context, native:)
      if callback
        app.run(&callback)
      else
        app.run
      end
    end

    # SPDX-SnippetEnd

    # Consider these "friendly": private, so app code does not call them, and
    # read by App through __send__.
    private attr_reader :state_manager, :invoke_handler_hook, :uri_scheme_protocols, # :nodoc:
      :async_uri_scheme_protocols, :setup_hook, :on_page_load_hook,
      :window_event_listeners, :webview_event_listeners, :rack_app, :menu_hook,
      :menu_event_listeners, :tray_icon_event_listeners

    # Whether an app with no menu gets the default one on macOS (friendly
    # reader; a predicate so it does not collide with the setter).
    private def macos_default_menu? # :nodoc:
      @enable_macos_default_menu
    end

    private def require_shareable!(block, method_name)
      return if Ractor.shareable?(block)

      raise Error, "#{method_name} block must be Ractor-shareable (use Ractor.shareable_proc)"
    end
  end
end

# SPDX-SnippetEnd
