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

    # Set the window title (delegates to native).
    def set_title(title)
      @native.set_title(title)
    end

    # Set the window size (delegates to native).
    def set_size(width, height)
      @native.set_size(width, height)
    end
  end
end

# SPDX-SnippetEnd
