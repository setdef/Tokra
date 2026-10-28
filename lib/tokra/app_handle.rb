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
    def initialize(manager, state_manager: nil, runtime_context: RuntimeContext.new) # :nodoc:
      @manager = manager
      @state_manager = state_manager
      @runtime_context = runtime_context
      @restart_on_exit = false
    end

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
        Tokra::Process.restart(env)
      end

      @restart_on_exit = true
      # The loop restarts the app once RunEvent::Exit is out (App#run).
      begin
        @runtime_context.request_exit(RESTART_EXIT_CODE)
      rescue Error::Runtime
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
      Tokra::Process.restart(env)
    end

    # Whether #restart or #request_restart asked the loop to restart the
    # app as it ends, Tauri's <tt>restart_on_exit</tt> flag
    # (manager/mod.rs:218).
    def restart_on_exit? # :nodoc:
      @restart_on_exit
    end
  end
end

# SPDX-SnippetEnd
