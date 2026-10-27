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

    # Requests application exit with optional exit code.
    #
    # Calls Kernel.exit, which raises SystemExit. Inside a running app the
    # native event loop catches it and ends with +code+, so plugins still
    # receive RunEvent::Exit. Called on another thread, it ends that thread,
    # and Ruby raises the same SystemExit in the main thread
    # (thread.c:726-732, 772-775 at Ruby v4.0.1), where the loop ends with
    # +code+ as Tauri's exit request does (app.rs:531-538). Tauri also emits
    # RunEvent::ExitRequested first; Tokra does not yet.
    #
    # === Example
    #
    #   handle.exit(0)
    def exit(code = 0)
      Kernel.exit(code)
    end
  end
end

# SPDX-SnippetEnd
