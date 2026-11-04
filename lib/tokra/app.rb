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
    include Listener
    include Emitter

    # The application handle, safe to pass between Ractors.
    attr_reader :handle

    # The application handle this App manages through, as Manager
    # requires. App is a Manager like AppHandle, Window, and Webview
    # (Tauri app.rs:683-701).
    #
    # === Example
    #
    #   app.app_handle.emit("ready", {})
    def app_handle
      @handle
    end

    # The app-level resources table, shared with AppHandle (Tauri
    # app.rs:683-687).
    #
    # === Example
    #
    #   rid = app.resources_table.add(image)
    def resources_table
      @handle.resources_table
    end

    # The per-app IPC invoke key verified on every message.
    #
    # The key is templated into the injected initialization scripts;
    # frontend messages carrying a different key are logged and dropped.
    # Use it when you build an invoke request by hand. Mirrors Tauri's
    # public App#invoke_key (app.rs:1040-1047).
    #
    # *Security*: never expose this key to third-party scripts. It grants
    # access to the backend from external URLs and iframes.
    #
    # === Example
    #
    #   message = { "cmd" => "greet", "__TAURI_INVOKE_KEY__" => app.invoke_key }
    def invoke_key
      @manager.invoke_key
    end

    # Runs necessary cleanup tasks before exiting the process, and returns
    # +nil+, as AppHandle#cleanup_before_exit does. <b>You should always
    # exit the Tokra app immediately after this method returns and not use
    # any Tokra APIs.</b>
    #
    # Mirrors Tauri's App::cleanup_before_exit (app.rs:1024-1038, 1114).
    #
    # === Example
    #
    #   app.cleanup_before_exit
    #   Process.exit!(0)
    def cleanup_before_exit
      @handle.cleanup_before_exit
    end

    # Runs the block on the main thread and returns +nil+, as
    # AppHandle#run_on_main_thread does.
    #
    # Mirrors Tauri's App::run_on_main_thread (app.rs:1137-1140).
    #
    # === Example
    #
    #   app.run_on_main_thread { puts "on the main thread" }
    def run_on_main_thread(&)
      @handle.run_on_main_thread(&)
    end

    # The native name of the display your windows are on, as
    # AppHandle#display_handle answers.
    #
    # Mirrors Tauri's <tt>HasDisplayHandle</tt> for App (app.rs:2361-2367).
    #
    # === Example
    #
    #   app.display_handle  #=> #<data Tokra::RawWindowHandle::WindowsDisplayHandle>
    def display_handle
      @handle.display_handle
    end

    # The system's main monitor, as AppHandle#primary_monitor answers.
    #
    # Mirrors Tauri's App::primary_monitor (app.rs:793-801).
    #
    # === Example
    #
    #   app.primary_monitor&.scale_factor  #=> 2.0
    def primary_monitor
      @handle.primary_monitor
    end

    # The monitor holding a desktop point, as
    # AppHandle#monitor_from_point answers.
    #
    # Mirrors Tauri's App::monitor_from_point (app.rs:804-810).
    #
    # === Example
    #
    #   app.monitor_from_point(0, 0)&.name  #=> "Built-in Retina Display"
    def monitor_from_point(x, y)
      @handle.monitor_from_point(x, y)
    end

    # Every monitor, as AppHandle#available_monitors answers.
    #
    # Mirrors Tauri's App::available_monitors (app.rs:813-823).
    #
    # === Example
    #
    #   app.available_monitors.map(&:name)  #=> ["Built-in Retina Display"]
    def available_monitors
      @handle.available_monitors
    end

    # The cursor's desktop position, as AppHandle#cursor_position answers.
    #
    # Mirrors Tauri's App::cursor_position (app.rs:825-840).
    #
    # === Example
    #
    #   app.cursor_position  #=> #<data Tokra::PhysicalPosition x=812.0, y=455.5>
    def cursor_position
      @handle.cursor_position
    end

    # Shows the whole app in +theme+, as AppHandle#set_theme does.
    #
    # Mirrors Tauri's App::set_theme (app.rs:842-869).
    #
    # === Example
    #
    #   app.set_theme(Tokra::Theme::Dark)
    def set_theme(theme)
      @handle.set_theme(theme)
    end

    # Creates a new App from a configured Builder and +context+, the
    # Tokra::Context the app is built from.
    #
    # This is called by Builder#build and should not be called directly.
    # <tt>native:</tt> can be injected for testing with mock native components.
    # Mirrors Tauri's Builder::build, which builds its AppManager from the
    # context (app.rs:2094-2127; manager/mod.rs:249-322).
    def initialize(builder, context, native: Native) # :nodoc:
      raise TypeError, "wrong argument type #{context.class} (expected Tokra::Context)" unless context.is_a?(Context)

      @manager = AppManager.new(config: context.config, package_info: context.package_info, pattern: context.pattern,
        dev: context.dev, webviews: {}, windows: {})
      # The thread that builds the app is its main thread until App#run
      # attaches the event loop, which makes the running thread the main one.
      @runtime_context = RuntimeContext.new(native:)
      @handle = AppHandle.new(@manager, state_manager: builder.__send__(:state_manager),
        runtime_context: @runtime_context, menu_event_listeners: builder.__send__(:menu_event_listeners),
        tray_icon_event_listeners: builder.__send__(:tray_icon_event_listeners),
        window_event_listeners: builder.__send__(:window_event_listeners), os_name:)
      @builder = builder
      # Set by App#set_activation_policy, on macOS (activation_policy.rb).
      @activation_policy = nil
      # Set when a requested restart ends the loop (#exit_requested).
      @restart_pending = false

      # Register core plugins, mirroring Tauri app.rs (App::build,
      # register_core_plugins at app.rs:1122-1135); Tokra has no path
      # plugin, so the event plugin comes first.
      @handle.plugin(Event::Plugin.new(@handle))
      @handle.plugin(Resources::Plugin.new(@handle))
      @handle.plugin(Image::Plugin.new(@handle))
      # The channel-data queue and its fetch command (app.rs:2260-2261)
      @handle.manage(Ipc::ChannelDataIpcQueue.new)
      @handle.plugin(Ipc::Channel::Plugin.new(@handle))
      # The menu commands the JavaScript API calls (app.rs:2262-2263)
      @handle.plugin(Menu::Plugin.new(@handle))
      # The tray commands the JavaScript API calls (app.rs:1132-1133)
      @handle.plugin(Tray::Plugin.new(@handle))
      # The command line a restart runs again (app.rs:2248-2249)
      @handle.manage(Env.default)
      # Store class references to avoid dynamic constant lookups
      @event_loop_class = native.const_get(:EventLoop)
    end

    # Runs the application event loop.
    #
    # Creates the native window and webview, then runs the event loop.
    # The block receives (handle, event) for each runtime event:
    # RunEvent::Ready before the loop starts, RunEvent::WindowEvent for
    # each WindowEvent (a resize, a move, focus, a close request, ...),
    # RunEvent::ExitRequested when the last window has closed or code
    # called AppHandle#exit, and RunEvent::Exit as the loop ends.
    # Registered plugins hear each one first.
    #
    # Each window the config's <tt>app.windows</tt> lists with +create+
    # set is built through WebviewWindowBuilder, in order, before the setup
    # hook, so the hook finds them; a config that lists none opens none.
    # Each takes its label, URL, title, and size. A builder error, such as
    # an invalid label or one already taken, ends this method with that
    # error, as an error the setup hook raises does. If the platform
    # refuses a window, the failure is warned and the app runs on, as
    # Tauri's does; with no window, nothing closes, so it never asks to
    # exit on its own, and AppHandle#exit ends it. (Tauri builds its config
    # windows in setup, on the runtime's Ready, and panics on its error or
    # logs a platform failure: app.rs:1297-1300, 2370-2384;
    # tauri-runtime-wry lib.rs:234-254, 3934-3943.)
    #
    # Closing the last window ends the app unless a handler calls
    # <tt>api.prevent_exit</tt> on the RunEvent::ExitRequested; then it
    # keeps running with no window until AppHandle#exit.
    #
    # The native loop never returns. When it ends, it raises SystemExit
    # with the loop's exit code, the way Kernel#exit ends a process, so
    # +ensure+ clauses and +at_exit+ hooks run and buffered output reaches
    # its pipe or file. Code after this call does not run; put shutdown
    # work in a RunEvent::Exit handler. A <tt>rescue Exception</tt> or
    # <tt>rescue SystemExit</tt> around this call catches the exit, and the
    # process keeps running unless you re-raise it.
    #
    # === Example
    #
    #   app.run do |_handle, event|
    #     puts "bye" if event.is_a?(Tokra::RunEvent::Exit)
    #   end
    def run(&callback)
      # Build the event loop first, as Tauri's runtime exists before its
      # setup hook runs, so the hook can ask for monitors and the cursor
      # (plan 041, decision 1).
      event_loop = @event_loop_class.new
      @runtime_context.window_target = event_loop
      # The loop's proxy next, so windows can be built from here on: each
      # webview's handlers send through it, and the runtime context sends
      # each window's creation (plan 052, decision 9). Attaching makes this
      # thread, already the main one, the loop's.
      proxy = event_loop.create_proxy
      @runtime_context.attach(proxy)
      # A theme the app asked for before its loop existed, which Tauri's
      # App sets on its loop at once (app.rs:864-868; plan 045,
      # decision 7).
      loop_theme = @handle.take_loop_theme
      event_loop.set_theme(loop_theme.first) if loop_theme

      # The builder's menu, now that tao has made NSApp (plan 042,
      # decision 7), before the setup hook, as Tauri's Builder::build does.
      install_app_menu

      # If a Rack app was configured, build the adapter that serves it
      # over tokra:// (ADR 004: Builder aggregates the app, App instantiates
      # the Handler). The Rack app runs on the main Ractor for now.
      rack_app = @builder.__send__(:rack_app)
      @rack_handler = ::Rack::Handler::Tokra.new(rack_app, proxy) if rack_app

      # The config's windows, then the setup hook, as Tauri's setup builds
      # them before it calls the hook (app.rs:2370-2384), so the hook finds
      # them.
      create_config_windows
      @builder.__send__(:setup_hook)&.call(self)

      # Before the loop runs, Tauri's App hands the policy to the runtime,
      # which sets it on tao's loop (app.rs:1160-1162, tauri-runtime-wry
      # lib.rs:3031-3036); this App builds the loop here, so it hands the
      # policy over now.
      activation_policy = @activation_policy
      event_loop.set_activation_policy(activation_policy.name) if activation_policy

      # Emit Ready event
      emit_run_event(RunEvent::Ready.new, callback)

      # Run the event loop, dispatching events. It never returns: when the
      # loop ends it raises SystemExit with the loop's exit code, so
      # RunEvent::Exit arrives from inside the loop as
      # Native::LoopDestroyedEvent, as in Tauri's runtime.
      begin
        event_loop.run(
          lambda { |event|
            dispatch_event(event, callback, proxy)
          }
        )
      ensure
        # The loop is gone: a call from another thread can no longer reach
        # the main thread, and one waiting for an answer will never get it.
        @runtime_context.close
      end
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Listener for App adapted from tauri/crates/tauri/src/app.rs

    # Calls the block with each +event+ sent to the app, as
    # AppHandle#listen does, and returns the handler's id.
    #
    # Mirrors Tauri's App::listen (app.rs:1055-1074).
    #
    # === Example
    #
    #   app.listen("component-loaded") { |event| puts event.payload }
    def listen(event, &)
      @handle.listen(event, &)
    end

    # Calls the block with the next +event+ sent to the app, as
    # AppHandle#once does (app.rs:1076-1086).
    def once(event, &)
      @handle.once(event, &)
    end

    # Removes the handler with +id+, as AppHandle#unlisten does
    # (app.rs:1088-1107).
    def unlisten(id)
      @handle.unlisten(id)
    end

    # SPDX-SnippetEnd

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: The app's menu and its events adapted from tauri/crates/tauri/src/app.rs,
    #                      window/mod.rs, and manager/menu.rs

    # Calls the block with the app handle and each Menu::MenuEvent, as
    # AppHandle#on_menu_event does.
    #
    # Mirrors Tauri's App::on_menu_event (app.rs:733-739).
    def on_menu_event(&)
      @handle.on_menu_event(&)
    end

    # The app's menu, or +nil+, as AppHandle#menu answers. +nil+ before
    # App#run, which sets the builder's menu (plan 042, decision 7).
    def menu
      @handle.menu
    end

    # Makes +menu+ the app's menu, as AppHandle#set_menu does.
    def set_menu(menu)
      @handle.set_menu(menu)
    end

    # Calls the block with the AppHandle and each Tray::TrayIconEvent, as
    # AppHandle#on_tray_icon_event does.
    #
    # Mirrors Tauri's App::on_tray_icon_event (app.rs:741-749).
    def on_tray_icon_event(&)
      @handle.on_tray_icon_event(&)
    end

    # The tray with +id+, or +nil+, as AppHandle#tray_by_id answers.
    def tray_by_id(id)
      @handle.tray_by_id(id)
    end

    # Takes the tray with +id+ away, as AppHandle#remove_tray_by_id does.
    def remove_tray_by_id(id)
      @handle.remove_tray_by_id(id)
    end

    # Takes the app's menu away, as AppHandle#remove_menu does.
    def remove_menu
      @handle.remove_menu
    end

    # Hides the app's menu bar, as AppHandle#hide_menu does.
    def hide_menu
      @handle.hide_menu
    end

    # Shows the app's menu bar again, as AppHandle#show_menu does.
    def show_menu
      @handle.show_menu
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: the config's windows adapted from tauri/crates/tauri/src/app.rs:2370-2375

    # Builds each window of the config's <tt>app.windows</tt> whose
    # +create+ is set, in order, as Tauri's setup does. Each takes the
    # label, URL, title, and size of its WindowConfig; plan 054a-4 builds
    # it through WebviewWindowBuilder.from_config with every row.
    private def create_config_windows
      config.app.windows.select(&:create).each do |window_config|
        WebviewWindowBuilder.new(self, window_config.label, window_config.url)
          .title(window_config.title)
          .inner_size(window_config.width, window_config.height)
          .build
      end
    end

    # SPDX-SnippetEnd

    # Builds the builder's menu, or Menu.default on macOS when it sets
    # none, and makes it the app's; on macOS also puts the app's menu on
    # NSApp, including one set before the loop existed
    # (app.rs:2094-2100, 2232-2245).
    private def install_app_menu
      hook = @builder.__send__(:menu_hook)
      natives = @runtime_context.menu_natives
      if hook.nil? && @builder.__send__(:macos_default_menu?) && Menu.os == :macos
        hook = -> (handle) { Menu::Menu.default(handle) }
      end
      if hook
        menu = hook.call(@handle)
        @handle.menu_manager.insert_menu_into_stash(menu)
        @handle.menu_manager.replace_menu(menu)
      end
      current = @handle.menu
      @handle.init_app_menu(current) if current && natives.nsapp?
    end

    # Calls the app's menu listeners, then each window's, then plugins and
    # the run callback with RunEvent::MenuEvent (app.rs:2436-2453,
    # 2488-2494).
    private def dispatch_menu_event(native_event, callback)
      event = Menu::MenuEvent.new(id: Menu::MenuId.new(value: native_event.id))
      menus = @handle.menu_manager
      menus.global_event_listeners.each { |listener| listener.call(@handle, event) }
      menus.event_listeners.each do |label, listener|
        window = @handle.get_window(label)
        listener.call(window, event) if window
      end
      emit_run_event(RunEvent::MenuEvent.new(event:), callback)
    end

    # Calls the app's tray listeners, then the listener of the tray the
    # event names, if the app still has it, then plugins and the run
    # callback with RunEvent::TrayIconEvent (app.rs:2453-2472, 2488-2494).
    private def dispatch_tray_icon_event(native_event, callback)
      event = Tray::TrayIconEvent.from_native(native_event)
      trays = @handle.tray_manager
      trays.global_event_listeners.each { |listener| listener.call(@handle, event) }
      trays.event_listeners.each do |id, listener|
        next unless event.id == id

        tray = @handle.tray_by_id(id)
        listener.call(tray, event) if tray
      end
      emit_run_event(RunEvent::TrayIconEvent.new(event:), callback)
    end

    # SPDX-SnippetEnd

    # Sends a run event to every registered plugin, then the user callback.
    #
    # Plugins hear events before the callback, matching Tauri's dispatch
    # order in on_event_loop_event (app.rs).
    private def emit_run_event(event, callback)
      @manager.plugins.on_event(@handle, event)
      callback&.call(@handle, event)
    end

    # The operating system name as Tauri's scripts expect it
    # (std::env::consts::OS values).
    private def os_name
      App.os_name
    end

    # The operating system this process runs on, as Tauri names it
    # (std::env::consts::OS values): the one place Tokra reads it, which
    # each App hands its WebviewManager.
    def self.os_name # :nodoc:
      case RUBY_PLATFORM
      when /darwin/ then "macos"
      when /linux/ then "linux"
      when /mingw|mswin/ then "windows"
      else "unknown"
      end
    end

    # Hands a native event to its handler. Answers the loop only for the
    # events whose answer it reads, +true+ ending it, and +nil+ otherwise.
    #
    # Each window event names its window, and each webview event its
    # webview, by label, and goes to the window or webview the manager
    # holds by that label, as Tauri's runtime resolves them
    # (tauri-runtime-wry lib.rs:4097-4150; manager/webview.rs:229-233,
    # 282-300). An event for a label the manager does not hold reaches
    # nothing.
    private def dispatch_event(event, callback, proxy)
      # Only these two answer the loop (ext/tokra/src/event_loop.rs ask).
      return window_destroyed(event.label, callback) if event.is_a?(Native::WindowDestroyedEvent)
      return exit_requested(event.code, callback) if event.is_a?(Native::ExitRequestedEvent)

      # Use is_a? instead of case/when to support mock event injection in tests
      if event.is_a?(Native::TaskEvent)
        @runtime_context.handle_task
      elsif event.is_a?(Native::HttpRequestEvent)
        dispatch_http_request(event, proxy)
      elsif event.is_a?(Native::IpcEvent)
        dispatch_ipc(event)
      elsif event.is_a?(Native::PageLoadEvent)
        dispatch_page_load(event)
      elsif event.is_a?(Native::WindowCloseEvent)
        close_requested(event.label, callback)
      elsif event.is_a?(Native::DragDropEvent)
        dispatch_webview_window_event(event.label, WindowEvent::DragDrop.new(event: drag_drop_event(event)), callback)
      elsif event.is_a?(Native::WebviewFocusedEvent)
        dispatch_webview_window_event(event.label, WindowEvent::Focused.new(focused: event.focused), callback)
      elsif event.is_a?(Native::WindowResizedEvent)
        window_resized(event.label, callback)
      elsif event.is_a?(Native::WindowMovedEvent)
        dispatch_window_event(event.label, WindowEvent::Moved.new(position: PhysicalPosition.new(x: event.x, y: event.y)),
          callback)
      elsif event.is_a?(Native::WindowFocusedEvent)
        dispatch_window_event(event.label, WindowEvent::Focused.new(focused: event.focused), callback)
      elsif event.is_a?(Native::WindowScaleFactorChangedEvent)
        dispatch_window_event(event.label, WindowEvent::ScaleFactorChanged.new(scale_factor: event.scale_factor,
          new_inner_size: PhysicalSize.new(width: event.width, height: event.height)), callback)
      elsif event.is_a?(Native::WindowThemeChangedEvent)
        theme_changed(event.label, event.theme, callback)
      elsif event.is_a?(Native::MenuEvent)
        dispatch_menu_event(event, callback)
      elsif event.is_a?(Native::TrayIconEvent)
        dispatch_tray_icon_event(event, callback)
      elsif event.is_a?(Native::LoopDestroyedEvent)
        # The runtime's loop-destroyed event becomes RunEvent::Exit
        # (tauri-runtime-wry lib.rs:4046-4047, app.rs:1304-1305). A
        # handler that raises does not keep a requested restart from
        # following it (app.rs:1306-1310); one that exits does, as
        # process::exit would.
        reporting { emit_run_event(RunEvent::Exit.new, callback) }
        # Then Tauri's cleanup_before_exit, before a requested restart
        # (app.rs:1304-1311; plan 049, decision 4).
        reporting { @handle.cleanup_before_exit }
        Tokra::Process.restart(env) if @restart_pending
      end
      nil
    end

    private def dispatch_http_request(event, proxy)
      # The ipc:// transport shares the HttpRequest event shape with the
      # tokra:// content protocol; route on the URI scheme (Plan 015 D1/D3).
      return dispatch_ipc_protocol(event, proxy) if ipc_protocol_request?(event.uri)

      sync_protocols = @builder.__send__(:uri_scheme_protocols)
      async_protocols = @builder.__send__(:async_uri_scheme_protocols)

      # Try sync protocol first (for backwards compatibility)
      # The context names the webview by the id wry handed the handler,
      # its label (manager/webview.rs:229-233).
      if sync_protocols && (handler = sync_protocols["tokra"])
        ctx = UriSchemeContext.new(app_handle: @handle, webview_label: event.label)
        response = handler.call(ctx, event)
        header_pairs = response.headers.map { |k, v| [k.to_s, v.to_s] } #: Array[[String, String]]
        proxy.respond(event.request_id, response.status, header_pairs, response.body)
      elsif async_protocols && (handler = async_protocols["tokra"])
        ctx = UriSchemeContext.new(app_handle: @handle, webview_label: event.label)
        responder = UriSchemeResponder.new(port: proxy, request_id: event.request_id)
        handler.call(ctx, event, responder)
      elsif (rack_handler = @rack_handler)
        # A configured Rack app is the tokra:// content server; the adapter
        # translates the request and responds through the proxy itself.
        rack_handler.call(event)
      end
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: IPC dispatch adapted from tauri/src/ipc/protocol.rs
    #                      and tauri/src/webview/mod.rs on_message

    # Handles a window.ipc.postMessage invoke (ipc/protocol.rs
    # handle_ipc_message).
    #
    # The message is read as serde_json reads it (Ipc::Json), so a message
    # Tauri rejects, such as one whose payload holds a lone surrogate
    # escape, never reaches a command. As in Tauri the failure is reported
    # in the page, not answered: the webview evaluates
    # <tt>console.error("JSON error: ...")</tt> (ipc/protocol.rs:287-291,
    # 422-430; error.rs:50-51), and the invoke's promise stays pending.
    #
    # Deviations (ADR 009): Tauri deserializes the message into a strict
    # Message struct; Tokra parses it as a whole Value and reads its
    # members. That is stricter for members Tauri does not know: serde
    # skips an unknown field with ignore_value, which checks neither its
    # strings' surrogates nor its numbers' range (serde_json de.rs:1100-1281),
    # so Tauri accepts a lone surrogate there and Tokra rejects it. It is
    # looser about shape: a message that is not an object is logged to
    # stderr, a missing +cmd+ is the empty command, and a message without
    # integer callback ids is fire-and-forget, so hand-rolled postMessage
    # calls keep working. A +cmd+ that is present but not a string fails
    # with Tauri's <tt>invalid type: ..., expected a string</tt>, without the
    # line and column serde gives it, which a parsed Value no longer knows.
    #
    # The command's body is the +payload+ member as sent, any JSON value,
    # so a typed array arrives as an Array of numbers, and its headers are
    # +options.headers+ (post_message_headers), read before the key check
    # as serde reads them (ipc/protocol.rs:233-242, 291-298). A missing
    # +payload+ is the empty object.
    #
    # The message goes to the webview whose label it carries, and a
    # message from a webview the manager no longer holds is dropped before
    # it is read (ipc/protocol.rs:185-186).
    private def dispatch_ipc(event)
      webview = @handle.webviews[event.label]
      return unless webview

      parsed = Ipc::Json.parse(event.message)
      return warn("failed to parse IPC message: not a JSON object") unless parsed.is_a?(Hash)

      cmd = parsed.fetch("cmd", "")
      unless cmd.is_a?(String)
        return report_ipc_message_error(
          webview, "JSON error: invalid type: #{Ipc::Unexpected.describe(cmd)}, expected a string"
        )
      end

      headers = post_message_headers(parsed["options"])

      received_key = parsed["__TAURI_INVOKE_KEY__"]
      unless received_key == @manager.invoke_key
        # Log and drop, exactly as Tauri does (webview/mod.rs on_message):
        # a frame the app did not initialize gets no response at all
        return warn(
          "__TAURI_INVOKE_KEY__ expected #{@manager.invoke_key} but received #{received_key}"
        )
      end

      empty_payload = {} #: Hash[String, json_value]
      body = parsed.fetch("payload", empty_payload)
      responder = build_ipc_responder(webview, parsed["callback"], parsed["error"],
        can_use_channel: can_use_channel_for_response?(cmd, parsed["options"]))

      route_invoke(webview, cmd, body, headers, responder, event.url)
    rescue Ipc::Json::Error, IpcMessageError => e
      report_ipc_message_error(webview, "JSON error: #{e.message}") if webview
    end

    # Raised internally when a postMessage's options.headers cannot become
    # a HeaderMap, the serde error Tauri reports as a JSON error
    # (ipc/protocol.rs:197-229). It never escapes App.
    class IpcMessageError < Error # :nodoc:
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2017 http-rs authors
    # SPDX-SnippetComment: Header name and value rules adapted from the http
    #                      crate 1.3.1, src/header/name.rs and value.rs

    # A header name the http crate accepts: 1 to 65535 RFC 9110 token
    # characters (http 1.3.1 header/name.rs:1009-1100, mod.rs:176).
    HEADER_NAME = /\A[!\#$%&'*+\-.^_`|~0-9A-Za-z]{1,65535}\z/n

    # A header value the http crate accepts from a str: no control
    # character but tab, and no DEL (header/value.rs:240-253, 585-587).
    HEADER_VALUE = /\A[^\x00-\x08\x0A-\x1F\x7F]*\z/n

    # A header value HeaderValue::to_str accepts: tab and visible ASCII
    # (header/value.rs:580-582).
    VISIBLE_ASCII = /\A[\t\x20-\x7E]*\z/n

    # SPDX-SnippetEnd

    # The headers of a postMessage invoke: its options.headers, read as
    # Tauri's RequestOptions reads them into a HeaderMap
    # (ipc/protocol.rs:197-229, 297). Names are lowercased as the http
    # crate stores them. A name or value it refuses, a value that is not a
    # string, or headers that are not an object raise IpcMessageError with
    # serde's message, without the line and column (Plan 033). Options
    # that are not an object, and a customProtocolIpcBlocked that is not a
    # bool, are ignored where serde would fail, as ADR 009 tolerates a
    # loose message shape.
    private def post_message_headers(options)
      empty = {} #: Hash[String, String]
      return empty.freeze unless options.is_a?(Hash) && options.key?("headers")

      headers = options["headers"]
      raise IpcMessageError, "invalid type: #{Ipc::Unexpected.describe(headers)}, expected a map" unless headers.is_a?(Hash)

      headers.each_with_object(empty) do |(name, value), map|
        raise IpcMessageError, "invalid type: #{Ipc::Unexpected.describe(value)}, expected a string" unless value.is_a?(String)
        unless HEADER_NAME.match?(name.b) && HEADER_VALUE.match?(value.b)
          raise IpcMessageError, "invalid header `#{name}` `#{value}`"
        end

        map[name.downcase] = value
      end.freeze
    end

    # Reports a postMessage Tauri could not read the way Tauri does: the
    # message, as a JSON string literal, logged with console.error in the
    # +webview+ that sent it (ipc/protocol.rs:422-430). serde_json's
    # Value::String and JSON.generate escape a String alike: quotes,
    # backslashes, and control characters, nothing else.
    private def report_ipc_message_error(webview, message)
      webview.eval("console.error(#{JSON.generate(message)})")
    end

    # Routes a parsed invoke to its handler, shared by both transports.
    #
    # Tauri routes the postMessage and ipc:// transports through one
    # method (webview/mod.rs on_message): plugin:-prefixed commands go to
    # the plugin store, everything else to the app invoke_handler, and an
    # unclaimed command rejects with <tt>Command NAME not found</tt>. Each
    # transport supplies only what differs: how it read the key, parsed
    # the payload, where it found the origin, and what its responder does.
    #
    # Tauri's on_message also resolves ACL/capabilities here. Tokra has no
    # capability system yet (TODO 001 #9), so as a stopgap it rejects every
    # invoke whose origin is not the app's own (local_url?) with Tauri's
    # release-build ACL message. That is stricter than Tauri, which lets a
    # remote origin call app commands when the app has no ACL manifest;
    # the stopgap goes away when capabilities land (ADR 010). The
    # channel-data fetch command is exempt, as Tauri exempts it from the
    # ACL (webview/mod.rs:1802-1806). On Linux the
    # postMessage origin is the webview's top-level URI, not the posting
    # frame's (wry's WebKitGTK backend reports it so, as Tauri sees it too),
    # so a foreign frame passes the check over postMessage there; ipc://
    # still rejects it by its Origin header.
    #
    # A handler that raises does not leave the frontend waiting: the error
    # is logged and, if the invoke has not responded yet, it rejects with
    # the exception message, the way a Tauri command returning Err does.
    #
    # The invoke's webview is +webview+, the one that sent it.
    private def route_invoke(webview, cmd, body, headers, responder, origin)
      plugin_name, command = plugin_command(cmd)
      invoke = Ipc::Invoke.new(
        command: command || cmd,
        payload: body,
        headers:,
        responder:,
        webview:
      )
      unless cmd == Ipc::Channel::FETCH_CHANNEL_DATA_COMMAND || local_url?(origin)
        return invoke.reject("Command #{cmd} not allowed by ACL")
      end

      handled = if plugin_name
        @manager.plugins.extend_api(plugin_name, invoke)
      else
        @builder.__send__(:invoke_handler_hook)&.call(invoke)
      end
      invoke.reject("Command #{command || cmd} not found") unless handled
    rescue => e
      warn("command #{cmd} failed: #{e.class}: #{e.message}")
      invoke&.reject(e.message)
    end

    # Builds a responder that evaluates Tauri's callback script in
    # +webview+, the calling one: success resolves the callback ID, failure
    # the error ID. Mirrors responder_eval (ipc/protocol.rs). Messages
    # without integer callback IDs (hand-rolled postMessage calls)
    # get no responder: fire and forget.
    #
    # A raw body is evaluated as a JSON number array, as Tauri's
    # format_result serializes a Vec<u8> on macOS and whenever the client
    # fell back from ipc:// (ipc/protocol.rs:390-402).
    #
    # Off macOS, when +can_use_channel+, a successful object or array
    # result, and a raw one, travel over Ipc::Channel.from_callback_fn
    # instead, as Tauri sends them (ipc/protocol.rs:371-407): a small one
    # evaluated, a large one fetched, raw bytes reaching the page as an
    # ArrayBuffer. A failed send is ignored, as Tauri's <tt>let _ =</tt>
    # does.
    #
    # As responder_eval does, a reply that cannot be built rejects with the
    # error's message instead, so the invoke still settles, and a failed
    # eval is ignored (<tt>let _ = webview.eval(...)</tt>).
    #
    # The responder runs synchronously on the Main Ractor and captures
    # the webview, so it must never cross a Ractor boundary. The Worker
    # Ractor phase (ADR 001) will swap this implementation for a proxy
    # round-trip without touching handlers.
    private def build_ipc_responder(webview, callback, error, can_use_channel: false)
      return nil unless callback.is_a?(Integer) && error.is_a?(Integer)

      over_channel = can_use_channel && os_name != "macos"
      lambda do |success, body|
        if success && over_channel && (Ipc::InvokeBody.raw?(body) || body.start_with?("{", "["))
          channel = Ipc::Channel.from_callback_fn(webview, callback)
          next channel.send(Ipc::Response.new(body)) # rubocop:disable Style/Send
        end

        script = begin
          json = Ipc::InvokeBody.raw?(body) ? JSON.generate(body.bytes) : body
          Ipc::FormatCallback.format_raw(success ? callback : error, json)
        rescue => e
          Ipc::FormatCallback.format(error, e.message.dup.force_encoding(Encoding::UTF_8).scrub)
        end
        webview.eval(script)
      rescue Tokra::Error
        nil
      end
    end

    # Tauri's can_use_channel_for_response (ipc/protocol.rs:337-339): any
    # command but the channel-data fetch, unless the client reports that
    # ipc:// failed. A customProtocolIpcBlocked that is not +true+ counts
    # as false, as ADR 009 tolerates a loose message shape.
    private def can_use_channel_for_response?(cmd, options)
      blocked = options.is_a?(Hash) && options["customProtocolIpcBlocked"] == true
      cmd != Ipc::Channel::FETCH_CHANNEL_DATA_COMMAND && !blocked
    end

    # Splits a plugin:NAME|command invoke into [NAME, command], or returns
    # +nil+ for an app command. The plugin store routes on NAME and the
    # plugin's extend_api hook sees the bare command, exactly as Tauri does
    # in webview/mod.rs (1793-1799): the name is the first | token and the
    # command the second, so <tt>plugin:a|b|c</tt> runs command +b+. A
    # missing | separator yields an empty command.
    private def plugin_command(cmd)
      return nil unless cmd.start_with?("plugin:")

      tokens = cmd.delete_prefix("plugin:").split("|", -1)
      [tokens[0] || "", tokens[1] || ""]
    end

    # The URL Tokra serves its own pages from: tokra://localhost on macOS
    # and Linux, http://tokra.localhost on Windows, where WebView2 serves
    # custom protocols over http (wry webview2 custom_protocol_workaround).
    # Mirrors tauri_protocol_url (manager/mod.rs:331-338); Tokra does not
    # enable wry's https scheme.
    private def tokra_protocol_url
      WebviewManager.tokra_protocol_url(os_name)
    end

    # Whether +url+, a String, belongs to the app: read by the url crate,
    # as Tauri reads the origin (ipc/protocol.rs:302, 491-499), with the
    # same scheme and domain as tokra_protocol_url, the first arm of
    # Tauri's is_local_url (webview/mod.rs:1680-1688). Tokra serves no
    # devUrl and routes every registered protocol through tokra://, so the
    # other arms do not apply. The domain is compared as the url crate
    # holds it, case and all: the crate lowercases the scheme and an http
    # host as it parses, but keeps a tokra:// host's case.
    private def local_url?(url)
      parsed = Ferro::Url::Url.parse(url)
      protocol = tokra_protocol_url
      parsed.scheme == protocol.scheme && parsed.domain == protocol.domain
    rescue Ferro::Url::ParseError
      false
    end

    # Raised internally when an ipc:// request is malformed: a missing or
    # non-numeric Tauri-Callback/Tauri-Error, a missing Tauri-Invoke-Key,
    # a missing or invalid Origin, unparseable JSON, or an unknown or
    # unimplemented content type. It mirrors the Err(String) arm of
    # parse_invoke_request (ipc/protocol.rs), surfaced to the client as
    # 500 text/plain. It never escapes App.
    class IpcProtocolError < Error # :nodoc:
    end

    # CORS headers stamped on every ipc:// reply, mirroring the shared
    # respond closure in ipc/protocol.rs (48-57): the client reads the
    # Tauri-Response header cross-origin, so it must be exposed.
    IPC_CORS_HEADERS = [
      ["Access-Control-Allow-Origin", "*"],
      ["Access-Control-Expose-Headers", "Tauri-Response"],
    ].freeze

    # The largest callback id: Tauri's CallbackFn wraps a u32
    # (ipc/mod.rs:586).
    MAX_CALLBACK_ID = (2 ** 32) - 1

    # A Content-Type token (RFC 9110 tchar), for telling a parseable media
    # type from garbage the way mime's parser does.
    MEDIA_TYPE = %r{\A[!\#$%&'*+\-.^_`|~0-9A-Za-z]+/[!\#$%&'*+\-.^_`|~0-9A-Za-z]+\z}

    # Serves the ipc:// custom protocol, Tauri's desktop-default invoke
    # transport (ipc/protocol.rs get handler). POST carries an invoke;
    # OPTIONS is the CORS preflight; any other method is 405.
    private def dispatch_ipc_protocol(event, proxy)
      case event.method
      when "POST"
        dispatch_ipc_protocol_post(event, proxy)
      when "OPTIONS"
        preflight = [["Access-Control-Allow-Headers", "*"]] #: Array[[String, String]]
        proxy.respond(event.request_id, 200, preflight + IPC_CORS_HEADERS, "")
      else
        respond_ipc_error(proxy, event.request_id, 405, "only POST and OPTIONS are allowed")
      end
    end

    # Handles a POST to ipc://: find the webview, parse per Tauri, verify
    # the invoke key, then route through the shared dispatcher with an HTTP
    # responder.
    #
    # The webview is the one whose label wry handed the handler, found
    # before anything else is read: a request from a webview the manager
    # no longer holds answers 500 text/plain <tt>failed to acquire webview
    # reference</tt>, whatever its key (ipc/protocol.rs:59-61, 152-160).
    #
    # A malformed request replies 500 text/plain with the parse error
    # (ipc/protocol.rs:143-151). A well-formed request with a mismatched key
    # logs Tauri's exact message and drops the responder with no reply
    # (webview/mod.rs:1728-1744). wry's responder has no Drop (wry
    # src/lib.rs:440-455), so nothing answers the request: the page's fetch
    # stays pending and the invoke never settles, as in Tauri. The client
    # does not fall back to postMessage, because its fetch never rejects.
    private def dispatch_ipc_protocol_post(event, proxy)
      webview = @handle.webviews[event.label]
      return respond_ipc_error(proxy, event.request_id, 500, "failed to acquire webview reference") unless webview

      cmd, invoke_key, origin, body = parse_ipc_protocol_request(event)

      unless invoke_key == @manager.invoke_key
        proxy.drop_response(event.request_id)
        return warn(
          "__TAURI_INVOKE_KEY__ expected #{@manager.invoke_key} but received #{invoke_key}"
        )
      end

      responder = build_ipc_protocol_responder(proxy, event.request_id)
      route_invoke(webview, cmd, body, request_headers(event.headers), responder, origin)
    rescue IpcProtocolError => e
      respond_ipc_error(proxy, event.request_id, 500, e.message)
    end

    # Parses an ipc:// POST into [cmd, invoke_key, origin, body], raising
    # IpcProtocolError on any malformed part, in Tauri's order
    # (ipc/protocol.rs:435-538): the content type, Tauri-Invoke-Key, Origin
    # (present and a valid URL), Tauri-Callback and Tauri-Error (present
    # and u32), then the body. The command is the percent-decoded URL path
    # (ipc/protocol.rs:443-445). The client reads the callback ids from its
    # own request, so Tokra only validates them.
    private def parse_ipc_protocol_request(event)
      headers = event.headers
      cmd = decode_ipc_command(event.uri)
      content_type = ipc_content_type(headers)

      invoke_key = http_header(headers, "Tauri-Invoke-Key")
      raise IpcProtocolError, "missing Tauri-Invoke-Key header" unless invoke_key
      raise IpcProtocolError, "Tauri invoke key header value must be a string" unless visible_ascii?(invoke_key)

      origin = ipc_origin(headers)
      validate_ipc_callback_id(headers, "Tauri-Callback", "callback")
      validate_ipc_callback_id(headers, "Tauri-Error", "error")

      [cmd, invoke_key, origin, parse_ipc_payload(content_type, event.body)]
    end

    # The command name: the URL path with the leading slash removed and
    # percent-decoded (ipc/protocol.rs:443-445). convertFileSrc encodes it
    # with encodeURIComponent (core.js). Like Tauri's percent_decode and
    # decode_utf8_lossy, decoding never fails: a stray % or an unencoded
    # character passes through, and invalid UTF-8 becomes U+FFFD.
    private def decode_ipc_command(uri)
      path = uri.sub(%r{\A[^:/?#]+://[^/?#]*}, "")[/\A[^?#]*/].to_s.delete_prefix("/")
      path.b.gsub(/%\h\h/) { |escape| escape[1, 2].to_s.to_i(16).chr }
        .force_encoding(Encoding::UTF_8).scrub
    end

    # The request content type, defaulting to application/octet-stream
    # when absent or not visible ASCII, which HeaderValue::to_str refuses
    # (ipc/protocol.rs:452-458). Like Tauri's Mime comparison,
    # parameters count: <tt>application/json; charset=utf-8</tt> is not
    # <tt>application/json</tt>. A value that is not a media type raises
    # <tt>unknown content type</tt>.
    private def ipc_content_type(headers)
      raw = http_header(headers, "Content-Type")
      return "application/octet-stream" unless raw && visible_ascii?(raw)

      essence, parameters = raw.split(";", 2)
      essence = essence.to_s.strip.downcase
      raise IpcProtocolError, "unknown content type" unless MEDIA_TYPE.match?(essence)

      parameters ? "#{essence};#{parameters}" : essence
    end

    # The Origin header, which must be present and a URL the url crate
    # parses, as Tauri parses it (ipc/protocol.rs:491-499); the crate
    # refuses a bare <tt>null</tt> origin.
    private def ipc_origin(headers)
      origin = http_header(headers, "Origin")
      raise IpcProtocolError, "missing Origin header" unless origin
      raise IpcProtocolError, "Origin header value must be a string" unless visible_ascii?(origin)
      raise IpcProtocolError, "Origin header is not a valid URL" unless url?(origin)

      origin
    end

    private def url?(value)
      Ferro::Url::Url.parse(value)
      true
    rescue Ferro::Url::ParseError
      false
    end

    # Parses the request body by content type into an InvokeBody
    # (ipc/protocol.rs:525-538). An octet-stream body is the raw bytes, an
    # empty one too, as a binary String, and never meets the JSON parser,
    # so a large binary argument costs no parsing. JSON parses as
    # serde_json parses it (Ipc::Json), so a body Tauri rejects, such as
    # invalid UTF-8 in a string, fails with serde_json's message before
    # any command runs, and an empty body is the empty object.
    private def parse_ipc_payload(content_type, body)
      case content_type
      when "application/json"
        empty = {} #: Hash[String, json_value]
        body.empty? ? empty : Ipc::Json.parse(body)
      when "application/octet-stream"
        body.b
      else
        raise IpcProtocolError, "content type #{content_type} is not implemented"
      end
    rescue Ipc::Json::Error => e
      raise IpcProtocolError, e.message
    end

    # Validates that a callback-id header is present and a u32, with the
    # grammar of Rust's u32::from_str: an optional + and ASCII digits, no
    # whitespace, within range (ipc/protocol.rs:501-520).
    private def validate_ipc_callback_id(headers, header_name, kind)
      value = http_header(headers, header_name)
      raise IpcProtocolError, "missing #{header_name} header" unless value
      raise IpcProtocolError, "Tauri #{kind} header value must be a string" unless visible_ascii?(value)
      return if value.match?(/\A\+?[0-9]+\z/) && value.to_i <= MAX_CALLBACK_ID

      raise IpcProtocolError, "Tauri #{kind} header value must be a numeric string"
    end

    # The request's headers as a command sees them (ipc/protocol.rs:
    # 540-548): every header, its name lowercased as the http crate stores
    # it, the first value of a repeated name winning as HeaderMap::get
    # returns the first.
    private def request_headers(pairs)
      headers = {} #: Hash[String, String]
      pairs.each { |(name, value)| headers[name.downcase] ||= value }
      headers.freeze
    end

    # Whether HeaderValue::to_str accepts +value+: visible ASCII and tab
    # only (http 1.3.1 header/value.rs:580-582). The command still gets
    # every value whole (request_headers); Tauri applies this only to the
    # headers it reads itself.
    private def visible_ascii?(value)
      value.b.match?(VISIBLE_ASCII)
    end

    # A case-insensitive header lookup over the [name, value] pairs the
    # native layer forwards. HTTP header names are case-insensitive, and the
    # http crate wry uses hands them over lowercased.
    private def http_header(headers, name)
      target = name.downcase
      pair = headers.find { |(key, _value)| key.downcase == target }
      pair&.last
    end

    # Builds the ipc:// responder: it answers the HTTP request rather than
    # evaluating runCallback, since the client reads the response and calls
    # runCallback itself (ipc-protocol.js). A raw body answers as
    # application/octet-stream, which the client reads as an ArrayBuffer;
    # JSON values and errors answer as application/json. The Tauri-Response
    # header tells success from error, and both reply 200
    # (ipc/protocol.rs:107-139).
    private def build_ipc_protocol_responder(proxy, request_id)
      lambda do |success, body|
        content_type = Ipc::InvokeBody.raw?(body) ? "application/octet-stream" : "application/json"
        headers = [
          ["Tauri-Response", success ? "ok" : "error"],
          ["Content-Type", content_type],
        ] #: Array[[String, String]]
        proxy.respond(request_id, 200, headers + IPC_CORS_HEADERS, body)
      end
    end

    # Replies to an ipc:// request with a plain-text error and the CORS
    # headers, used for the 500 malformed, 500 unknown-webview, and 405
    # non-POST paths.
    private def respond_ipc_error(proxy, request_id, status, message)
      headers = [["Content-Type", "text/plain"]] #: Array[[String, String]]
      proxy.respond(request_id, status, headers + IPC_CORS_HEADERS, message)
    end

    # True when a forwarded HTTP request is an ipc:// invoke. On Windows
    # the page fetches http://ipc.localhost/, but wry reverts that to
    # ipc://localhost/ before calling the protocol handler (webview2
    # prepare_request), so every platform arrives here as ipc://.
    private def ipc_protocol_request?(uri)
      uri.start_with?("ipc://")
    end

    # SPDX-SnippetEnd

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Page load dispatch adapted from tauri/src/manager/webview.rs prepare_pending_webview

    # A page started or finished loading in the webview labeled as the
    # event says: the builder's hook hears it with the Webview, then every
    # plugin's on_page_load; a webview the manager no longer holds is
    # nothing to tell (manager/webview.rs:282-300; plugin.rs:965-972).
    # The payload's URL is wry's String as the url crate parses it, and a
    # load whose URL the crate refuses is dropped, as tauri-runtime-wry
    # drops it (lib.rs:4843-4855).
    private def dispatch_page_load(event)
      url = page_url(event.url)
      webview = @handle.webviews[event.label]
      return unless url && webview

      payload = PageLoadPayload.new(url:, started: event.started?)
      @builder.__send__(:on_page_load_hook)&.call(webview, payload)
      @manager.plugins.on_page_load(webview, payload)
    end

    # +text+ as the url crate parses it, frozen, or +nil+ when it cannot.
    private def page_url(text)
      Ferro::Url::Url.parse(text).freeze
    rescue Ferro::Url::ParseError
      nil
    end

    # SPDX-SnippetEnd

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Close, destroy, and exit requests adapted from
    # tauri-runtime-wry/src/lib.rs (handle_event_loop, on_close_requested,
    # on_window_close) and tauri/crates/tauri/src/app.rs (on_event_loop_event)

    # Asks the listeners of the window labeled +label+, then plugins and
    # the run callback, whether the window may close, then closes its
    # native window unless one prevented it (on_close_requested,
    # lib.rs:4262-4290). Its Destroyed event follows from the platform. A
    # window already closed is no longer in the store, and the request is
    # dropped, as Tauri's is.
    private def close_requested(label, callback)
      window = @handle.windows[label]
      return unless window

      api = CloseRequestApi.new
      event = WindowEvent::CloseRequested.new(api:)
      reporting do
        window.window_event_listeners.each { |listener| listener.call(event) }
        emit_run_event(RunEvent::WindowEvent.new(label: window.label, event:), callback)
      end
      window.native.close unless api.prevented?
    end

    # The native window labeled +label+ is gone. The manager drops it and
    # its webviews first (on_window_close, manager/mod.rs:651-658), then the run
    # callback hears Destroyed, then the window's listeners
    # (lib.rs:4126-4148), and the runtime drops the webviews
    # (lib.rs:4172). When it was the last window in the runtime's store,
    # which a window whose creation failed never joined
    # (RuntimeContext#window_destroyed), the app asks to exit with no code
    # (lib.rs:4171-4185). A window built by hand through
    # Native::Window.new and put in the manager never joins that store, so
    # closing the last builder-made window exits while it is still on
    # screen. Answers the loop: +true+ ends it.
    private def window_destroyed(label, callback)
      last = @runtime_context.window_destroyed(label)
      window = @handle.windows.delete(label)
      return false unless window

      webviews = @handle.webviews.values.select { |webview| webview.window.label == label }
      webviews.each { |webview| @handle.webviews.delete(webview.label) }
      reporting { notify_window_event(window, WindowEvent::Destroyed.new, callback) }
      webviews.each { |webview| webview.native.close }
      return false unless last

      exit_requested(nil, callback)
    end

    # Asks plugins and the run callback whether the app may exit with
    # +code+, +nil+ when the last window closed (lib.rs:4172-4185,
    # 4215-4227). Answers the loop: +true+ ends it, with +code+ or 0.
    private def exit_requested(code, callback)
      api = ExitRequestApi.new(code)
      reporting { emit_run_event(RunEvent::ExitRequested.new(code:, api:), callback) }
      ends = !api.prevented?
      # The loop ends for a requested restart, so its end restarts the app
      # (app.rs:1308-1310). A handler that exited instead, as restart on
      # the main thread does, never gets here: in Tauri its process::exit
      # ends the process before the Exit arm runs (Plan 039, decision 9).
      @restart_pending = true if ends && code == RESTART_EXIT_CODE && @handle.restart_on_exit?
      ends
    end

    # SPDX-SnippetEnd

    # Runs the block, reporting a StandardError it raises the way the
    # native loop reports a failed event (ext/tokra/src/event_loop.rs
    # Turn#report), so the default that follows still happens: Tauri's
    # runtime proceeds unless a handler prevented first.
    private def reporting
      yield
    rescue => e
      warn(e.full_message(highlight: false))
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Window events adapted from tauri-runtime-wry/src/lib.rs (handle_event_loop)

    # Tells the run callback, then the listeners of the window labeled
    # +label+, of +event+ (lib.rs:4126-4148). A window already closed hears
    # nothing more.
    private def dispatch_window_event(label, event, callback)
      window = @handle.windows[label]
      notify_window_event(window, event, callback) if window
    end

    # A webview's own report, a drop on it or (Windows) its focus, as a
    # window event of the window holding it now, which Webview#window
    # names, as Tauri's runtime sends a webview's synthesized window event
    # to the webview's window (lib.rs:4097-4122). A webview the manager no
    # longer holds reports nothing.
    private def dispatch_webview_window_event(webview_label, event, callback)
      webview = @handle.webviews[webview_label]
      dispatch_window_event(webview.window.label, event, callback) if webview
    end

    private def notify_window_event(window, event, callback)
      emit_run_event(RunEvent::WindowEvent.new(label: window.label, event:), callback)
      window.window_event_listeners.each { |listener| listener.call(event) }
    end

    # The theme tao reports, mapped as map_theme maps it, any theme but
    # dark being light (lib.rs:578-584). On Windows each webview of the
    # window labeled +label+ takes the theme too, once the listeners have
    # heard it (lib.rs:4153-4166).
    private def theme_changed(label, name, callback)
      theme = (name == "dark") ? Theme::Dark : Theme::Light
      window = @handle.windows[label]
      return unless window

      notify_window_event(window, WindowEvent::ThemeChanged.new(theme:), callback)
      window.webviews.each do |webview|
        native = webview.native
        next unless native.respond_to?(:set_theme)

        begin
          native.set_theme(theme.name)
        rescue RuntimeError => e
          warn("failed to set theme: #{e.message}")
        end
      end
    end

    # The window's inner size, as tauri-runtime-wry's parse reads it in
    # place of tao's; a window whose native window is already closed has
    # none, and its Resized is dropped (lib.rs:557-575).
    private def window_resized(label, callback)
      window = @handle.windows[label]
      return unless window

      size = inner_size_of(window)
      dispatch_window_event(label, WindowEvent::Resized.new(size:), callback) if size
    end

    # The window's inner size, or +nil+ once its native window is gone.
    private def inner_size_of(window)
      window.inner_size
    rescue Error::Runtime
      nil
    end

    # wry's drag and drop as Tauri's DragDropEvent, with Pathnames and
    # f64 positions (lib.rs:4669-4692).
    private def drag_drop_event(native_event)
      position = PhysicalPosition.new(x: native_event.x.to_f, y: native_event.y.to_f)
      paths = native_event.paths.map { |path| Pathname.new(path) }
      case native_event.event
      when "enter" then DragDropEvent::Enter.new(paths, position)
      when "over" then DragDropEvent::Over.new(position)
      when "drop" then DragDropEvent::Drop.new(paths, position)
      else DragDropEvent::Leave.new
      end
    end

    # SPDX-SnippetEnd
  end
end

# SPDX-SnippetEnd
