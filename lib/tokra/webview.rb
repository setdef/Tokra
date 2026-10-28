# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Webview structure adapted from tauri/crates/tauri/src/webview/mod.rs

module Tokra
  # Webview wrapper holding native webview reference and ResourceTable.
  #
  # Mirrors Tauri's Webview<R> struct. Each webview owns its own
  # resources_table for storing image resources and other managed objects.
  #
  # Plugins access the calling webview through Invoke#webview:
  #
  #   def invoke_handler(invoke)
  #     table = invoke.webview.resources_table
  #     rid = table.add(MyResource.new)
  #     invoke.resolve(rid)
  #   end
  #
  class Webview
    include Manager

    # The unique label identifying this webview.
    attr_reader :label

    # The app handle for accessing shared state.
    attr_reader :app_handle

    # The native wry WebView handle.
    attr_reader :native

    # Creates a new Webview wrapper.
    #
    # +label+:: a unique identifier for this webview (e.g., "main").
    # +native+:: the Native::WebView handle from wry.
    # +window+:: the parent Window wrapper.
    # +app_handle+:: provides access to app-level state and config.
    def initialize(label:, native:, window:, app_handle:)
      @label = label
      @native = native
      @window = window
      @app_handle = app_handle
      @resources_table = ResourceTable.new
    end

    # The parent window containing this webview.
    def window
      @window
    end

    # Per-webview resource table for managed resources.
    #
    # Resources added here are scoped to this webview. The table
    # is cleared when the webview is destroyed.
    def resources_table
      @resources_table
    end

    # Evaluates JavaScript in this webview and returns +nil+.
    #
    # From another thread the script travels to the main thread and this
    # method returns without waiting for it to run. A script the webview
    # fails to evaluate is logged, never raised, as Tauri's runtime logs it
    # (tauri-runtime-wry lib.rs:1773-1783, 3642-3646). Raises
    # Error::Runtime when the event loop has ended.
    #
    # Mirrors Tauri's Webview::eval (webview/mod.rs:1896-1902).
    #
    # === Example
    #
    #   webview.eval("document.title = 'Ready'")
    def evaluate(script)
      native = @native
      @app_handle.runtime_context.run_on_main_thread do
        native.eval(script)
      rescue RuntimeError => e
        warn(e.message)
      end
    end
    alias eval evaluate

    # Paints the webview's background, behind the page, with +color+, a
    # Tokra::Color, or white for +nil+, and returns +nil+. Runs as
    # #evaluate does; anything but a Color or +nil+ raises TypeError on the
    # calling thread. A color the webview fails to take is logged, never
    # raised, as Tauri's runtime logs it.
    #
    # wry does not implement it on macOS, so there it does nothing. On
    # Windows an alpha other than 0 is taken as 255. Window#set_background_color
    # colors the window behind the webview (plan 041, decision 2).
    #
    # Mirrors Tauri's Webview::set_background_color (webview/mod.rs:2069-2083;
    # tauri-runtime-wry lib.rs:1829-1838, 3745-3750).
    #
    # === Example
    #
    #   webview.set_background_color(Tokra::Color.new(30, 30, 30, 255))
    def set_background_color(color)
      native = @native
      unless color.nil? || color.is_a?(Color)
        raise TypeError, "wrong argument type #{color.class} (expected Tokra::Color)"
      end

      rgba = color && [color.red, color.green, color.blue, color.alpha] #: Native::Window::rgba?
      @app_handle.runtime_context.run_on_main_thread do
        native.set_background_color(rgba)
      rescue RuntimeError => e
        warn("failed to set webview background color: #{e.message}")
      end
    end

    # Runs the block on the main thread and returns +nil+, as
    # AppHandle#run_on_main_thread does.
    #
    # Mirrors Tauri's Webview::run_on_main_thread (webview/mod.rs:1356-1363).
    #
    # === Example
    #
    #   Thread.new { webview.run_on_main_thread { webview.eval("refresh()") } }
    def run_on_main_thread(&)
      @app_handle.runtime_context.run_on_main_thread(&)
    end
  end
end

# SPDX-SnippetEnd
