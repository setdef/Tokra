# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles the title bar rows, the tabbing identifier, and the
# traffic-light position only for macOS (window/mod.rs:853-879;
# webview_window.rs:828-883), so they exist only there (ADR 011; plan
# 052, decision c4).
return unless Tokra::App.os_name == "macos"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: The macOS builder rows adapted from tauri/crates/tauri/src/window/mod.rs,
#                      webview/webview_window.rs, and tauri-runtime-wry/src/lib.rs

module Tokra
  class WindowBuilder # :nodoc:
    # Tauri's WindowBuilder::title_bar_style (window/mod.rs:853-858;
    # lib.rs:1151-1176).
    def title_bar_style(style)
      expect(style, TitleBarStyle)
      set(:title_bar_style, style.name)
    end

    # Tauri's WindowBuilder::hidden_title (window/mod.rs:861-866;
    # lib.rs:1184-1188).
    def hidden_title(hidden)
      flag(:hidden_title, hidden)
    end

    # Tauri's WindowBuilder::tabbing_identifier (window/mod.rs:874-879;
    # lib.rs:1190-1195, 4348-4356).
    def tabbing_identifier(identifier)
      expect(identifier, String)
      set(:tabbing_identifier, identifier.dup)
    end
  end

  class WebviewWindowBuilder
    # Draws the window's title bar in +style+, a TitleBarStyle, and
    # returns the builder. Anything else raises TypeError.
    #
    # Visible, the default, draws an opaque title bar over a content view
    # that fills the window; Transparent a transparent title bar above
    # the content; and Overlay a transparent title bar over it, for a page
    # that draws its own. With Visible and Overlay the window's inner size
    # includes the title bar, so the page is shorter than #inner_size by its
    # height. Defined only on macOS, as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::title_bar_style
    # (webview_window.rs:828-833, tauri-runtime-wry lib.rs:1151-1176).
    #
    # === Example
    #
    #   builder.title_bar_style(Tokra::TitleBarStyle::Overlay)
    def title_bar_style(style)
      forward { |rows| rows.title_bar_style(style) }
    end

    # Hides the window's title text, or shows it, and returns the
    # builder. Defined only on macOS, as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::hidden_title
    # (webview_window.rs:865-870, tauri-runtime-wry lib.rs:1184-1188).
    #
    # === Example
    #
    #   builder.hidden_title(true)
    def hidden_title(hidden)
      forward { |rows| rows.hidden_title(hidden) }
    end

    # Groups the window as a tab with your other windows whose identifier
    # is +identifier+, a String, and returns the builder.
    #
    # A window with no identifier, or a transparent or undecorated one,
    # never joins tabs on its own. Anything but a String raises TypeError.
    # Defined only on macOS, as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::tabbing_identifier
    # (webview_window.rs:878-883), whose runtime turns AppKit's automatic
    # tabbing off for those windows (tauri-runtime-wry lib.rs:4348-4356).
    #
    # === Example
    #
    #   builder.tabbing_identifier("documents")
    def tabbing_identifier(identifier)
      forward { |rows| rows.tabbing_identifier(identifier) }
    end

    # Moves the window's close, minimize, and zoom buttons to +position+,
    # a LogicalPosition or a PhysicalPosition from the window's top-left
    # corner, and returns the builder. Anything else raises TypeError.
    #
    # It takes effect in a decorated window whose title bar is
    # TitleBarStyle::Overlay. Defined only on macOS, as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::traffic_light_position
    # (webview_window.rs:838-847), a webview attribute wry turns into
    # with_traffic_light_inset (tauri-runtime-wry lib.rs:4943-4946).
    #
    # === Example
    #
    #   builder.title_bar_style(Tokra::TitleBarStyle::Overlay).traffic_light_position(Tokra::LogicalPosition.new(x: 16, y: 20))
    def traffic_light_position(position)
      webview(:traffic_light_position, Dpi.position_dimensions(position))
    end
  end
end

# SPDX-SnippetEnd
