# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles Window::set_overlay_icon only for Windows
# (window/mod.rs:2113-2124), so it exists only where the native window
# has it (ADR 011; plan 045, decision 5).
return unless Tokra::Native::Window.method_defined?(:set_overlay_icon)

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Window::set_overlay_icon adapted from tauri/crates/tauri/src/window/mod.rs

module Tokra
  class Window
    # Shows +icon+, a Tokra::Image, over the corner of this window's
    # taskbar button, and returns +nil+. +nil+ takes it away. Each window
    # has its own. Runs as #center does.
    #
    # The image becomes an icon on the calling thread, as in Tauri, so an
    # image whose pixels do not fill its width and height raises
    # Error::Runtime "invalid icon: ..." here, as #set_icon does, and
    # nothing is sent. Anything but an Image or +nil+ raises TypeError.
    # Defined only on Windows, as in Tauri.
    #
    # Mirrors Tauri's Window::set_overlay_icon (window/mod.rs:2113-2124),
    # which converts the image before it sends it (tauri-runtime-wry
    # lib.rs:2364-2371, 3504-3507).
    #
    # === Example
    #
    #   window.set_overlay_icon(Tokra::Image.from_path("icons/unread.png"))
    def set_overlay_icon(icon)
      native = @native
      expect(icon, Image) if icon
      overlay = icon && begin
        Native::Icon.from_rgba(icon.rgba, icon.width, icon.height)
      rescue RuntimeError => e
        raise Error::Runtime, "invalid icon: #{e.message}"
      end
      dispatch { native.set_overlay_icon(overlay) }
    end
  end

  class WebviewWindow
    # The window's Window#set_overlay_icon, where Tauri's WebviewWindow sends it
    # (webview_window.rs:2167-2171).
    def_delegators :@window, :set_overlay_icon
  end
end

# SPDX-SnippetEnd
