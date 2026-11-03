# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles WindowBuilder::transparent and WebviewBuilder::transparent
# everywhere but macOS, where they need the macos-private-api feature
# (window/mod.rs:625-634; webview/mod.rs:1021-1030;
# webview_window.rs:1073-1086). Whether Tokra builds that feature in is
# plan 052's question 2, so until it is answered the row does not exist
# on macOS (decision c4).
return if Tokra::App.os_name == "macos"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: The transparent rows adapted from tauri/crates/tauri/src/window/mod.rs,
#                      webview/webview_window.rs, and tauri-runtime-wry/src/lib.rs

module Tokra
  class WindowBuilder # :nodoc:
    # Tauri's WindowBuilder::transparent (window/mod.rs:625-634;
    # lib.rs:1070-1074).
    def transparent(transparent)
      flag(:transparent, transparent)
    end
  end

  class WebviewBuilder # :nodoc:
    # Tauri's WebviewBuilder::transparent (webview/mod.rs:1021-1030;
    # lib.rs:4627).
    def transparent(transparent)
      flag(:transparent, transparent)
    end
  end

  class WebviewWindowBuilder
    # Makes the window and its webview transparent, or not, and returns
    # the builder. In a transparent window, colors whose alpha is below
    # 255 show what is behind it. Not defined on macOS, where Tauri needs
    # its macos-private-api feature, which Tokra does not build in yet.
    #
    # Mirrors Tauri's WebviewWindowBuilder::transparent
    # (webview_window.rs:1073-1086), which sets both.
    #
    # === Example
    #
    #   builder.transparent(true).decorations(false)
    def transparent(transparent)
      @window_builder.transparent(transparent)
      webview_row { |rows| rows.transparent(transparent) }
    end
  end
end

# SPDX-SnippetEnd
