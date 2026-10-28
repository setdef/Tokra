# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AppHandle structure adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Handle to the running application, safe to pass between Ractors.
  #
  # Provides access to application state and control methods.
  # Includes the Manager module for shared interface.
  class AppHandle
    include Manager

    # Creates a new AppHandle with the given AppManager.
    #
    # This is called internally by App and should not be called directly.
    def initialize(manager, state_manager: nil, runtime_context: RuntimeContext.new, menu_event_listeners: [], # :nodoc:
      tray_icon_event_listeners: []
    )
      @manager = manager
      @state_manager = state_manager
      @runtime_context = runtime_context
      @restart_on_exit = false
      @menu_manager = MenuManager.new(runtime_context, menu_event_listeners)
      @tray_manager = TrayManager.new(tray_icon_event_listeners)
    end

    # The app's menus and their listeners, which Tauri's AppManager holds
    # (manager/menu.rs).
    attr_reader :menu_manager # :nodoc:

    # The app's tray icons and their listeners, which Tauri's AppManager
    # holds (manager/tray.rs).
    attr_reader :tray_manager # :nodoc:

    private attr_reader :manager

    # The dispatcher that carries window and webview calls to the main
    # thread. Window and Webview reach it here, as Tauri's handles reach
    # the runtime through the app handle's runtime_handle (app.rs).
    attr_reader :runtime_context # :nodoc:

    # Runs the block on the main thread and returns +nil+.
    #
    # The operating system ties every window and webview to the main
    # thread, so work on another thread that needs one hands it over with
    # this method. Called on the main thread, the block runs at once.
    # Called on any other thread, it runs when the event loop gets to it,
    # in the order you sent it, and this method returns without waiting.
    # Raises Error::Runtime when the event loop has ended.
    #
    # Window and Webview send their own native calls this way, so you need
    # it only for your own main-thread work.
    #
    # Mirrors Tauri's AppHandle::run_on_main_thread (app.rs:452-458).
    #
    # === Example
    #
    #   Thread.new do
    #     report = build_report
    #     handle.run_on_main_thread { handle.emit("report", report) }
    #   end
    def run_on_main_thread(&)
      @runtime_context.run_on_main_thread(&)
    end

    # Returns self since this is already an app handle.
    def app_handle
      self
    end

    # Adds state to the application, keyed by its class.
    #
    # Plugins and commands share long-lived objects (a native clipboard, a
    # database handle) through managed state instead of globals. Each class
    # holds one instance: the first one managed wins.
    #
    # Returns +true+ if the state was stored, +false+ if an instance of the
    # same class is already managed. Raises +Error+ if no StateManager.
    # Mirrors Tauri's Manager::manage (lib.rs:694-699).
    #
    # === Example
    #
    #   handle.manage(Counter.new)  #=> true
    #   handle.manage(Counter.new)  #=> false; the first Counter stays
    #   handle.state(Counter)
    def manage(state)
      mgr = @state_manager
      raise Error, "No StateManager available" unless mgr

      mgr.set(state)
    end

    # Retrieves managed state by class.
    #
    # Raises +KeyError+ if not found, +Error+ if no StateManager.
    def state(klass)
      mgr = @state_manager
      raise Error, "No StateManager available" unless mgr

      mgr.get(klass)
    end

    # Retrieves managed state by class, or +nil+ if not found.
    def try_state(klass)
      @state_manager&.try_get(klass)
    end

    # Returns the application configuration.
    def config
      @manager.config
    end

    # Returns all managed webviews.
    def webviews
      @manager.webviews
    end

    # Returns all managed windows.
    def windows
      @manager.windows
    end

    # Fetches a window by label.
    #
    # Returns nil if no window with that label exists.
    def get_window(label)
      @manager.windows[label]
    end

    # Fetches a webview by label.
    #
    # Returns nil if no webview with that label exists.
    def get_webview(label)
      @manager.webviews[label]
    end

    # The native name of the display your windows are on: a
    # RawWindowHandle value.
    #
    # Windows answers with a RawWindowHandle::WindowsDisplayHandle and
    # macOS with a RawWindowHandle::AppKitDisplayHandle, neither of which
    # carries anything. Linux answers with the X11 or Wayland display. A
    # library asks for it beside a window's handle; Window#display_handle
    # answers the same.
    #
    # From another thread this asks the main thread and waits for its
    # answer. Raises RawWindowHandle::HandleError::Unavailable before the
    # app has a window, and when called from another thread once the event
    # loop has ended; on the main thread it still answers then.
    #
    # On X11 every caller shares one Xlib connection, and Xlib is not
    # thread-safe, so use the display only on the main thread.
    #
    # On X11, tao opens a new connection to the X server for every display
    # handle and never closes it. Tokra asks tao once and answers every
    # later call with that first display, which stays open as long as the
    # app runs (ADR 013).
    #
    # Mirrors Tauri's <tt>HasDisplayHandle</tt> for AppHandle
    # (app.rs:2353-2359), which reads it from the runtime's event loop
    # (tauri-runtime-wry lib.rs:2656-2660).
    #
    # *Deviations*: Tauri reads the display on the calling thread, from
    # the event loop; Tokra's event loop is inside its run loop then, and
    # Tokra's native objects answer only the main thread (ADR 012), so the
    # app's first window answers, on the main thread. Tauri's event loop
    # exists before the setup hook runs; Tokra builds its window after it,
    # so the setup hook gets Unavailable.
    #
    # === Example
    #
    #   handle.display_handle  #=> #<data Tokra::RawWindowHandle::XlibDisplayHandle display=94500000000, screen=0>
    def display_handle
      window = windows.each_value.first
      raise RawWindowHandle::HandleError::Unavailable unless window

      native = window.native
      RawWindowHandle.display_handle(@runtime_context.getter { native.raw_display_handle })
    rescue Error::Runtime
      raise RawWindowHandle::HandleError::Unavailable
    end

    # The system's main monitor, as a Monitor, or +nil+ when the platform
    # cannot tell (Wayland).
    #
    # It needs no window: the event loop answers, on the main thread. From
    # another thread the question travels there and this waits for the
    # answer. Raises Error::Runtime "failed to receive message from
    # webview" before App#run has built the event loop or after it has
    # ended, and "failed to send message to the webview" when another
    # thread asks after the loop has ended.
    #
    # Mirrors Tauri's AppHandle::primary_monitor (app.rs:793-801), which
    # the runtime reads from its event loop's window target
    # (tauri-runtime-wry lib.rs:2662-2669). *Deviation*: Tauri reads it on
    # the calling thread and never fails; Tokra's native objects answer
    # only the main thread (ADR 012; plan 041, decision 1).
    #
    # === Example
    #
    #   handle.primary_monitor.name  #=> "Built-in Retina Display"
    def primary_monitor
      answer = window_target_getter(&:primary_monitor).first
      answer && Monitor.from_native(answer)
    end

    # The monitor that holds the desktop point (+x+, +y+), in physical
    # pixels, as a Monitor, or +nil+ when none does. Answers as
    # #primary_monitor does.
    #
    # Mirrors Tauri's AppHandle::monitor_from_point (app.rs:804-810;
    # tauri-runtime-wry lib.rs:2671-2678).
    #
    # === Example
    #
    #   handle.monitor_from_point(10.0, 10.0).position  #=> #<data Tokra::PhysicalPosition x=0, y=0>
    def monitor_from_point(x, y)
      x = Float(x)
      y = Float(y)
      answer = window_target_getter { |target| target.monitor_from_point(x, y) }.first
      answer && Monitor.from_native(answer)
    end

    # Every monitor attached to the computer, as an Array of Monitors.
    # Answers as #primary_monitor does.
    #
    # Mirrors Tauri's AppHandle::available_monitors (app.rs:813-823;
    # tauri-runtime-wry lib.rs:2680-2688).
    #
    # === Example
    #
    #   handle.available_monitors.size  #=> 2
    def available_monitors
      window_target_getter(&:available_monitors).map { |entry| Monitor.from_native(entry) }
    end

    # The mouse cursor's position, as a PhysicalPosition relative to the
    # top-left corner of the desktop: the main monitor's on Windows and
    # macOS, the leftmost monitor's on X11. It can be negative. Wayland
    # cannot tell and answers 0, 0.
    #
    # Answers on the main thread as #primary_monitor does, and raises
    # Error::Runtime "failed to get cursor position" when the platform
    # fails to read it.
    #
    # Mirrors Tauri's AppHandle::cursor_position (app.rs:825-840), which
    # asks the event loop's window target through the loop
    # (tauri-runtime-wry lib.rs:212-217, 2690-2695, 3999-4004).
    #
    # === Example
    #
    #   handle.cursor_position  #=> #<data Tokra::PhysicalPosition x=812.0, y=455.5>
    def cursor_position
      position = window_target_getter(&:cursor_position).first
      raise Error::Runtime, Error::Runtime::FAILED_TO_GET_CURSOR_POSITION unless position

      x, y = position
      PhysicalPosition.new(x:, y:)
    end

    # Returns the app-level resources table.
    #
    # This is the final fallback in the hierarchy: webview → window → app.
    # Created lazily on first access.
    def resources_table
      @resources_table ||= ResourceTable.new
    end

    # Adds a plugin to the application.
    #
    # The plugin's extend_api hook receives IPC commands invoked as
    # <tt>plugin:NAME|command</tt>, where NAME is the plugin's name.
    # Registering a plugin with an existing name replaces it.
    #
    # Returns +true+ if a same-named plugin was replaced, +false+ otherwise.
    # Mirrors Tauri's AppHandle::plugin (app.rs).
    #
    # === Example
    #
    #   handle.plugin(MyPlugin.new(handle))
    def plugin(plugin)
      @manager.plugins.register(plugin)
    end

    # Removes the plugin with the given name from the application.
    #
    # Returns +true+ if a plugin was removed, +false+ otherwise.
    # Mirrors Tauri's AppHandle::remove_plugin (app.rs).
    #
    # === Example
    #
    #   handle.remove_plugin("my-plugin")  #=> true
    def remove_plugin(name)
      @manager.plugins.unregister(name)
    end

    # Returns the path resolver for app directories.
    #
    # Provides cross-platform access to app-specific directories like
    # log directories, config directories, etc.
    def path
      @path ||= Path::Resolver.new(config)
    end

    # Emits an event to all webviews.
    #
    # Mirrors Tauri's AppHandle#emit which broadcasts to all webviews.
    def emit(event_name, payload)
      js = Tokra::Native.emit_js_script(event_name, payload.to_json)
      webviews.each_value { |wv| wv.eval(js) }
    end

    # Asks the app to exit with +code+ and returns +nil+.
    #
    # Exits the app by triggering RunEvent::ExitRequested and
    # RunEvent::Exit. The request travels through the event loop, from any
    # thread, so your code after this call runs; the loop then emits
    # RunEvent::ExitRequested with +code+ to plugins and the App#run
    # callback. Unless a handler calls <tt>api.prevent_exit</tt>, the loop
    # ends, plugins hear RunEvent::Exit, and the process ends with +code+.
    # Called before App#run, the request waits for the loop.
    #
    # Once the event loop has ended there is no one left to ask, so this
    # calls Kernel.exit(+code+), which raises SystemExit, as Tauri falls
    # back to <tt>process::exit</tt>.
    #
    # A plain Kernel#exit in a handler still ends the loop at once without
    # asking, as <tt>std::process::exit</tt> would in a Tauri app.
    #
    # Mirrors Tauri's AppHandle::exit (app.rs:531-538), which sends
    # Message::RequestExit through the runtime (tauri-runtime-wry
    # lib.rs:2623-2629, 4215-4227). Tauri's loop then ends with status 0
    # whatever the code, since tao's ControlFlow::Exit is ExitWithCode(0);
    # Tokra ends with +code+, as Ruby's own exit does (Plan 038,
    # decision 5).
    #
    # === Example
    #
    #   handle.exit(0)
    def exit(code = 0)
      @runtime_context.request_exit(code)
    rescue Error::Runtime
      cleanup_trays
      Kernel.exit(code)
    end

    # Restarts the app, and never returns.
    #
    # Restarts the app by triggering RunEvent::ExitRequested with code
    # RESTART_EXIT_CODE and RunEvent::Exit, then runs the app's command
    # line again (Process.restart): the same Ruby, script, and arguments,
    # in a new process, while this one ends with status 0.
    #
    # Called on the main thread, inside an event handler, the events cannot
    # be delivered in order, so this skips them and restarts at once; the
    # Kernel.exit that ends the process still runs +ensure+ clauses, and
    # inside the event loop RunEvent::Exit follows it as it follows any
    # exit. Called on any other thread, it asks the loop and then waits
    # there for the loop to end the process. Use #request_restart to have
    # the events delivered reliably.
    #
    # Mirrors Tauri's AppHandle::restart (app.rs:540-570).
    #
    # === Example
    #
    #   Thread.new { handle.restart if update_installed? }
    def restart
      if @runtime_context.main_thread?
        # The process ends here, so the loop's end must not restart it again.
        @restart_on_exit = false
        cleanup_trays
        Tokra::Process.restart(env)
      end

      @restart_on_exit = true
      # The loop restarts the app once RunEvent::Exit is out (App#run).
      begin
        @runtime_context.request_exit(RESTART_EXIT_CODE)
      rescue Error::Runtime
        cleanup_trays
        Tokra::Process.restart(env)
      end
      loop { sleep }
    end

    # Asks the app to restart, and returns +nil+.
    #
    # Restarts the app by triggering RunEvent::ExitRequested with code
    # RESTART_EXIT_CODE and RunEvent::Exit. Like #exit, the request travels
    # through the event loop from any thread, so your code after this call
    # runs. Handlers cannot prevent this exit: ExitRequestApi#prevent_exit
    # does nothing for RESTART_EXIT_CODE. Once plugins and the App#run
    # callback have heard RunEvent::Exit, the app runs its command line
    # again (Process.restart) and this process ends with status 0. Called
    # before App#run, the request waits for the loop; once the loop has
    # ended, the app restarts at once.
    #
    # Mirrors Tauri's AppHandle::request_restart (app.rs:572-582).
    #
    # === Example
    #
    #   handle.request_restart
    def request_restart
      @restart_on_exit = true
      # The loop restarts the app once RunEvent::Exit is out (App#run).
      @runtime_context.request_exit(RESTART_EXIT_CODE)
      nil
    rescue Error::Runtime
      cleanup_trays
      Tokra::Process.restart(env)
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: The app's menu adapted from tauri/crates/tauri/src/app.rs
    #                      and manager/mod.rs

    # Calls the block with this handle and each Menu::MenuEvent, a click on
    # any menu item, and returns +nil+.
    #
    # Each block hears every click, in the order the blocks came, before
    # each window's Window#on_menu_event block and before the run
    # callback hears it as RunEvent::MenuEvent. The blocks run on the main
    # thread.
    #
    # Mirrors Tauri's on_menu_event (app.rs:733-739).
    #
    # === Example
    #
    #   handle.on_menu_event { |handle, event| handle.exit(0) if event.id == "quit" }
    def on_menu_event(&handler)
      @menu_manager.on_menu_event(handler)
    end

    # The app's menu, or +nil+.
    #
    # Mirrors Tauri's menu (app.rs:877-880).
    def menu
      @menu_manager.menu
    end

    # Makes +menu+ the app's menu and returns the menu it replaces, or
    # +nil+.
    #
    # On macOS the menu goes at the top of the screen. On Windows and
    # Linux every window that shows the app's menu, or no menu, shows this
    # one instead. Before App#run builds the event loop, macOS gets the
    # menu once the loop exists (plan 042, decision 7).
    #
    # Mirrors Tauri's set_menu (app.rs:886-923).
    #
    # === Example
    #
    #   handle.set_menu(Tokra::Menu::Menu.default(handle))
    def set_menu(menu)
      previous = remove_menu
      @menu_manager.insert_menu_into_stash(menu)
      @menu_manager.replace_menu(menu)
      if @runtime_context.menu_natives.nsapp?
        on_nsapp { init_app_menu(menu) }
      else
        windows.each_value do |window|
          next unless window.has_app_wide_menu? || window.menu.nil?

          window.set_menu(menu)
          window.replace_window_menu(Window::WindowMenu.new(is_app_wide: true, menu:))
        end
      end
      previous
    end

    # Takes the app's menu away and returns it, or +nil+.
    #
    # Mirrors Tauri's remove_menu (app.rs:925-962).
    def remove_menu
      current = @menu_manager.menu
      if current
        if @runtime_context.menu_natives.nsapp?
          app = @runtime_context.menu_natives.app
          native_menu = current.native #: Native::Menu
          on_nsapp { app.remove_menu_for_nsapp(native_menu) }
        else
          windows.each_value do |window|
            next unless window.has_app_wide_menu?

            window.remove_menu
            window.replace_window_menu(nil)
          end
        end
      end
      previous = @menu_manager.take_menu
      remove_menu_from_stash_by_id(previous&.id)
      previous
    end

    # Hides the app's menu bar on every window that shows it, and returns
    # +nil+. On macOS it does nothing.
    #
    # Mirrors Tauri's hide_menu (app.rs:964-983).
    def hide_menu
      return nil if @runtime_context.menu_natives.nsapp? || @menu_manager.menu.nil?

      windows.each_value { |window| window.hide_menu if window.has_app_wide_menu? }
      nil
    end

    # Shows the app's menu bar again on every window that shows it, and
    # returns +nil+. On macOS it does nothing.
    #
    # Mirrors Tauri's show_menu (app.rs:985-1004).
    def show_menu
      return nil if @runtime_context.menu_natives.nsapp? || @menu_manager.menu.nil?

      windows.each_value { |window| window.show_menu if window.has_app_wide_menu? }
      nil
    end

    # Puts +menu+ on NSApp, with its Window and Help submenus as NSApp's,
    # on the main thread. macOS only.
    #
    # Mirrors Tauri's init_app_menu (app.rs:2336-2350).
    def init_app_menu(menu) # :nodoc:
      app = @runtime_context.menu_natives.app
      native_menu = menu.native #: Native::Menu
      Menu.run_main_thread(self) { app.init_menu_for_nsapp(native_menu) }
      window_menu = menu.get(Menu::WINDOW_SUBMENU_ID)
      window_menu.set_as_windows_menu_for_nsapp if window_menu.is_a?(Menu::Submenu)
      help_menu = menu.get(Menu::HELP_SUBMENU_ID)
      help_menu.set_as_help_menu_for_nsapp if help_menu.is_a?(Menu::Submenu)
      nil
    end

    # Drops the menu with the id +id+ from the stash unless the app or a
    # window still shows it (manager/mod.rs:689-702).
    private def remove_menu_from_stash_by_id(id)
      return nil unless id

      used_by_a_window = windows.each_value.any? { |window| window.menu_in_use?(id) }
      @menu_manager.remove_menu_from_stash(id) unless @menu_manager.menu_in_use?(id) || used_by_a_window
      nil
    end

    # Runs +work+ on the main thread once the event loop exists, ignoring
    # its errors, as Tauri's set_menu ignores init_app_menu's. Before then
    # there is no NSApp to change: tao makes it with the loop, and App#run
    # puts the app's menu on it then (plan 042, decision 7).
    private def on_nsapp(&work)
      return nil unless @runtime_context.window_target

      @runtime_context.run_on_main_thread do
        work.call
      rescue Error
        nil
      end
    end

    # SPDX-SnippetEnd

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: The app's tray icons adapted from tauri/crates/tauri/src/app.rs

    # Calls the block with this handle and each Tray::TrayIconEvent, from
    # any of the app's trays, and returns +nil+.
    #
    # Each block hears every event, in the order the blocks came, before
    # the tray's own Tray::TrayIcon#on_tray_icon_event block and before
    # the run callback hears it as RunEvent::TrayIconEvent. The blocks run
    # on the main thread.
    #
    # Mirrors Tauri's on_tray_icon_event (app.rs:741-749).
    #
    # === Example
    #
    #   handle.on_tray_icon_event { |handle, event| handle.tray_by_id(event.id)&.set_visible(false) }
    def on_tray_icon_event(&handler)
      @tray_manager.on_tray_icon_event(handler)
    end

    # The tray with +id+, a String or Tray::TrayIconId, or +nil+.
    #
    # Mirrors Tauri's tray_by_id (app.rs:751-760).
    def tray_by_id(id)
      @tray_manager.tray_by_id(self, id)
    end

    # Takes the tray with +id+ off the system tray and out of the app, and
    # returns it, or +nil+ when the app has none with that id. The
    # returned tray does nothing any more (plan 043, decision 6).
    #
    # Mirrors Tauri's remove_tray_by_id (app.rs:762-774), where dropping
    # the returned tray takes it off the system tray.
    #
    # === Example
    #
    #   handle.remove_tray_by_id("main")
    def remove_tray_by_id(id)
      @tray_manager.remove_tray_by_id(self, id)
    end

    # Takes every tray off the system tray, as Tauri's cleanup_before_exit
    # does by dropping them before the process ends (app.rs:1026-1028;
    # plan 043, decision 7). A tray that fails to close is skipped: the
    # app is ending.
    def cleanup_trays # :nodoc:
      @tray_manager.close_all(self)
    end

    # SPDX-SnippetEnd

    # Whether #restart or #request_restart asked the loop to restart the
    # app as it ends, Tauri's <tt>restart_on_exit</tt> flag
    # (manager/mod.rs:218).
    def restart_on_exit? # :nodoc:
      @restart_on_exit
    end

    # Runs +query+ with the event loop's window target on the main thread
    # and answers it. Without a loop the answer is +nil+, which raises, as
    # an answer that never came does.
    private def window_target_getter(&query)
      context = @runtime_context
      answer = context.getter do
        target = context.window_target
        target && query.call(target)
      end
      raise Error::Runtime, Error::Runtime::FAILED_TO_RECEIVE_MESSAGE if answer.nil?

      answer
    end
  end
end

# SPDX-SnippetEnd
