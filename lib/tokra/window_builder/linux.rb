# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles WindowBuilder::transient_for only for Linux and the BSDs
# (window/mod.rs:814-824; webview_window.rs:791-801), so it exists only on
# Linux, the one of them Tokra builds for (ADR 011; plan 052, decision c4).
return unless Tokra::App.os_name == "linux"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: The Linux builder row adapted from tauri/crates/tauri/src/window/mod.rs,
#                      webview/webview_window.rs, and tauri-runtime-wry/src/lib.rs

module Tokra
  class WindowBuilder # :nodoc:
    # Tauri's WindowBuilder::transient_for, the relation #parent sets on
    # Linux (window/mod.rs:814-824; lib.rs:1133-1143).
    def transient_for(parent)
      expect(parent, Window)
      set(:parent, open_native(parent))
    end
  end

  class WebviewWindowBuilder
    # Makes the window transient for +parent+, a WebviewWindow, as a
    # dialog is for the window it belongs to, and returns the builder.
    #
    # The window manager keeps it above +parent+. On Linux #parent sets
    # the same relation. It asks for +parent+'s native window at once and
    # raises Error::Runtime "failed to receive message from webview" if
    # +parent+ is closed. Defined only on Linux, as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::transient_for
    # (webview_window.rs:791-801, window/mod.rs:814-824).
    #
    # === Example
    #
    #   builder.transient_for(app.get_webview_window("main"))
    def transient_for(parent)
      @window_builder.transient_for(webview_window(parent).window)
      self
    end
  end
end

# SPDX-SnippetEnd
