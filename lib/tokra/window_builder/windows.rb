# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles WindowBuilder::owner and drag_and_drop only for Windows
# (window/mod.rs:760-764, 845-850; webview_window.rs:745-749, 820-825),
# so they exist only there (ADR 011; plan 052, decision c4).
return unless Tokra::App.os_name == "windows"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: The Windows builder rows adapted from tauri/crates/tauri/src/window/mod.rs,
#                      webview/webview_window.rs, and tauri-runtime-wry/src/lib.rs

module Tokra
  class WindowBuilder # :nodoc:
    # Tauri's WindowBuilder::owner, the same owner #parent sets on Windows
    # (window/mod.rs:760-764; lib.rs:1115-1119).
    def owner(owner)
      expect(owner, Window)
      set(:parent, open_native(owner))
    end

    # Tauri's WindowBuilder::drag_and_drop (window/mod.rs:845-850;
    # lib.rs:1145-1149).
    def drag_and_drop(enabled)
      flag(:drag_and_drop, enabled)
    end
  end

  class WebviewWindowBuilder
    # Makes +owner+, a WebviewWindow, the window's owner, and returns the
    # builder.
    #
    # An owned window stays above its owner, hides when its owner is
    # minimized, and closes when its owner does. On Windows #parent sets
    # the same owner. It asks for +owner+'s native window at once and
    # raises Error::Runtime "failed to receive message from webview" if
    # +owner+ is closed. Defined only on Windows, as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::owner (webview_window.rs:745-749,
    # window/mod.rs:760-764).
    #
    # === Example
    #
    #   builder.owner(app.get_webview_window("main"))
    def owner(owner)
      @window_builder.owner(webview_window(owner).window)
      self
    end

    # Turns the window's own file drag and drop on or off, and returns the
    # builder. It is on unless you turn it off. Defined only on Windows,
    # as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::drag_and_drop
    # (webview_window.rs:820-825, tauri-runtime-wry lib.rs:1145-1149).
    #
    # === Example
    #
    #   builder.drag_and_drop(false)
    def drag_and_drop(enabled)
      forward { |rows| rows.drag_and_drop(enabled) }
    end
  end
end

# SPDX-SnippetEnd
