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

    # Evaluate JavaScript in this webview.
    def evaluate(script)
      @native.eval(script)
    end
    alias eval evaluate
  end
end

# SPDX-SnippetEnd
