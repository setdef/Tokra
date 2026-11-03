# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: ScrollBarStyle adapted from tauri-runtime/src/webview.rs

module Tokra
  # The native scroll bars a webview draws.
  #
  # Each platform draws its own scroll bars under the page's CSS. On
  # Windows a page can ask for the thin Fluent scroll bars that float over
  # the content, as newer Windows apps have. Pass one of these to
  # WebviewWindowBuilder#scroll_bar_style; CSS that styles the scroll bars
  # applies on top.
  #
  # Default is the only style everywhere; Windows also has FluentOverlay,
  # which, as in Tauri, exists only there. ScrollBarStyle.new is private.
  #
  # Mirrors Tauri's <tt>tauri::webview::ScrollBarStyle</tt> (tauri-runtime
  # src/webview.rs:174-192).
  #
  # === Example
  #
  #   builder.scroll_bar_style(Tokra::ScrollBarStyle::Default)
  class ScrollBarStyle < Data.define(:name)
    extend ClosedEnum

    ##
    # The browser's own scroll bars.
    Default = new(name: "Default")

    # Tauri compiles FluentOverlay only for Windows (tauri-runtime
    # src/webview.rs:186-191), so it exists only there (ADR 011; plan 052,
    # decision e1-6).
    if App.os_name == "windows"
      # Fluent's thin scroll bars, drawn over the page. They need the
      # WebView2 Runtime 125.0.2535.41 or newer, and do nothing on an
      # older one. Give every webview that shares a data directory the
      # same style.
      FluentOverlay = new(name: "FluentOverlay")
    end

    close
  end
end

# SPDX-SnippetEnd
