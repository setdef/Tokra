# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Window structure adapted from tauri/crates/tauri/src/window/mod.rs

module Tokra
  # Window wrapper holding native window reference and ResourceTable.
  #
  # Mirrors Tauri's Window<R> struct. Each window owns its own
  # resources_table, used as fallback if webview table doesn't have resource.
  class Window
    include Manager

    # The unique label identifying this window.
    attr_reader :label

    # The app handle for accessing shared state.
    attr_reader :app_handle

    # The native tao/winit Window handle.
    attr_reader :native

    # Creates a new Window wrapper.
    #
    # +label+:: a unique identifier for this window (e.g., "main").
    # +native+:: the Native::Window handle from tao/winit.
    # +app_handle+:: provides access to app-level state and config.
    def initialize(label:, native:, app_handle:)
      @label = label
      @native = native
      @app_handle = app_handle
      @resources_table = ResourceTable.new
    end

    # Per-window resource table.
    def resources_table
      @resources_table
    end

    # Sets the window title and returns +nil+.
    #
    # From another thread the change travels to the main thread and this
    # method returns without waiting for it, as Tauri's set_title does
    # (window/mod.rs, tauri-runtime-wry lib.rs:2093-2098). Raises
    # Error::Runtime when the event loop has ended.
    #
    # === Example
    #
    #   window.set_title("Saved")
    def set_title(title)
      native = @native
      dispatch { native.set_title(title) }
    end

    # Sets the window's inner size, in logical pixels, and returns +nil+.
    #
    # From another thread the change travels to the main thread and this
    # method returns without waiting for it, as Tauri's set_size does
    # (tauri-runtime-wry lib.rs:2211-2216). Raises Error::Runtime when the
    # event loop has ended.
    #
    # === Example
    #
    #   window.set_size(1024.0, 768.0)
    def set_size(width, height)
      native = @native
      dispatch { native.set_size(width, height) }
    end

    # Keeps the window above every other window, or lets it go back
    # among them, and returns +nil+.
    #
    # A palette, a timer, or a video you watch while you work stays in
    # sight when another app comes to the front. On macOS the window
    # floats above other apps' windows without taking the keyboard from
    # them. On Linux the window manager may ignore the request, and on
    # Wayland it does nothing.
    #
    # From another thread the change travels to the main thread and this
    # method returns without waiting for it, as Tauri's
    # Window::set_always_on_top does (window/mod.rs:1866-1873,
    # tauri-runtime-wry lib.rs:2184-2189, 3390). Raises Error::Runtime when
    # the event loop has ended.
    #
    # === Example
    #
    #   window.set_always_on_top(true)
    def set_always_on_top(always_on_top)
      native = @native
      dispatch { native.set_always_on_top(always_on_top) }
    end

    # Lets the cursor's clicks and moves pass through the window to
    # whatever is behind it, or catches them again, and returns +nil+.
    #
    # An overlay that shows something over your work, such as a heads-up
    # display or a floating clock, should not swallow the clicks meant for
    # the app underneath. Pass +true+ and the window ignores the cursor;
    # pass +false+ to catch its events again, as every window does at
    # first.
    #
    # From another thread the change travels to the main thread and this
    # method returns without waiting for it, as Tauri's
    # Window::set_ignore_cursor_events does (window/mod.rs:2087-2094,
    # tauri-runtime-wry lib.rs:2326-2331, 3461-3463). Raises Error::Runtime
    # when the event loop has ended.
    #
    # === Example
    #
    #   window.set_ignore_cursor_events(true)
    def set_ignore_cursor_events(ignore)
      native = @native
      dispatch { native.set_ignore_cursor_events(ignore) }
    end

    # The window title.
    #
    # From another thread this asks the main thread and waits for its
    # answer. Raises Error::Runtime when the event loop has ended, or ends
    # before it answers.
    #
    # Mirrors Tauri's Window::title (window/mod.rs:1493-1495), a getter
    # the runtime answers on the main thread (tauri-runtime-wry
    # lib.rs:1942-1944, 3293).
    #
    # === Example
    #
    #   window.title  #=> "Tokra"
    def title
      native = @native
      @app_handle.runtime_context.getter { native.title }
    end

    # The native name of this window: a RawWindowHandle value.
    #
    # A library that opens a dialog in front of your window, or draws into
    # it, asks for the window's handle. On Windows the answer is a
    # RawWindowHandle::Win32WindowHandle, on macOS a
    # RawWindowHandle::AppKitWindowHandle, and on Linux a
    # RawWindowHandle::XlibWindowHandle under X11 or a
    # RawWindowHandle::WaylandWindowHandle under Wayland.
    #
    # From another thread this asks the main thread and waits for its
    # answer, as Tauri's does. Called from another thread once the event
    # loop has ended, it raises RawWindowHandle::HandleError::Unavailable,
    # where Tauri raises it for a closed window: a Tokra window closes only
    # when its loop ends. On the main thread, in a RunEvent::Exit handler
    # or an +at_exit+ hook, it still answers, since the window still
    # exists.
    #
    # The handle names the window only while it is open. RawWindowHandle
    # says how to use one safely.
    #
    # Mirrors Tauri's <tt>HasWindowHandle</tt> for Window
    # (window/mod.rs:943-949), which asks the runtime's dispatcher, a
    # getter answered on the main thread, and turns a failed getter into
    # <tt>HandleError::Unavailable</tt> (tauri-runtime-wry
    # lib.rs:1852-1856, 2012-2018, 3320-3326).
    #
    # === Example
    #
    #   window.window_handle  #=> #<data Tokra::RawWindowHandle::AppKitWindowHandle ns_view=105553116266496>
    def window_handle
      native = @native
      RawWindowHandle.window_handle(@app_handle.runtime_context.getter { native.raw_window_handle })
    rescue Error::Runtime
      raise RawWindowHandle::HandleError::Unavailable
    end

    # The native name of the display this window is on: a RawWindowHandle
    # value, as AppHandle#display_handle answers.
    #
    # Pair it with #window_handle when a library asks for both, as a
    # dialog that names its parent window does.
    #
    # Mirrors Tauri's <tt>HasDisplayHandle</tt> for Window
    # (window/mod.rs:951-957), which asks the app handle.
    #
    # === Example
    #
    #   window.display_handle  #=> #<data Tokra::RawWindowHandle::AppKitDisplayHandle>
    def display_handle
      @app_handle.display_handle
    end

    # Runs the block on the main thread and returns +nil+, as
    # AppHandle#run_on_main_thread does.
    #
    # Mirrors Tauri's Window::run_on_main_thread (window/mod.rs:1087-1094).
    #
    # === Example
    #
    #   Thread.new { window.run_on_main_thread { window.native.set_title("Ready") } }
    def run_on_main_thread(&)
      @app_handle.runtime_context.run_on_main_thread(&)
    end

    # Sends a native call to the main thread without waiting for it.
    private def dispatch(&call)
      @app_handle.runtime_context.run_on_main_thread(&call)
    end
  end
end

# SPDX-SnippetEnd
