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
