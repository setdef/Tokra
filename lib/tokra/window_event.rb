# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WindowEvent adapted from tauri/crates/tauri/src/window/mod.rs
#                      and tauri-runtime/src/window.rs

module Tokra
  # What happened to a window: the events Window#on_window_event,
  # Builder#on_window_event, and RunEvent::WindowEvent carry.
  #
  # Each variant is a value class. A Rust variant with one unnamed field
  # names it after what it holds (+size+, +position+, +focused+, +theme+,
  # +event+); one with named fields keeps them.
  #
  # Mirrors Tauri's <tt>WindowEvent</tt> (tauri-runtime window.rs, re-exported
  # as tauri::WindowEvent).
  module WindowEvent
    # The window has been requested to close, by its close button or by
    # Window#close. Call <tt>api.prevent_close</tt>, a CloseRequestApi, to
    # keep it open; otherwise it closes once every handler has returned.
    # Mirrors Tauri's <tt>WindowEvent::CloseRequested { api }</tt>
    # (app.rs:114-118).
    CloseRequested = Data.define(:api)

    # The window has been destroyed. The app no longer lists it when your
    # handlers hear this. Mirrors Tauri's <tt>WindowEvent::Destroyed</tt>
    # (app.rs:119-120).
    Destroyed = Data.define

    # The window gained focus, +focused+ +true+, or lost it. On Windows it
    # follows the webview's focus, as Tauri's runtime does. Mirrors
    # Tauri's <tt>WindowEvent::Focused(bool)</tt>.
    Focused = Data.define(:focused)

    # The window moved; +position+ is the PhysicalPosition of its inner
    # area's top-left corner. Mirrors Tauri's
    # <tt>WindowEvent::Moved(PhysicalPosition<i32>)</tt>.
    Moved = Data.define(:position)

    # The window's inner area changed size; +size+ is the PhysicalSize
    # Window#inner_size answers, which on macOS is the webview's, as Tauri's
    # runtime reports it. Mirrors Tauri's
    # <tt>WindowEvent::Resized(PhysicalSize<u32>)</tt>.
    Resized = Data.define(:size)

    # The window's scale factor changed, to +scale_factor+, for example
    # when it moved to another monitor; +new_inner_size+ is the
    # PhysicalSize its inner area takes. Mirrors Tauri's
    # <tt>WindowEvent::ScaleFactorChanged { scale_factor, new_inner_size }</tt>.
    ScaleFactorChanged = Data.define(:scale_factor, :new_inner_size)

    # Files are being dragged over the window, or were dropped on it;
    # +event+ is a DragDropEvent. Tokra's webview fills its window, so its
    # drops are the window's, as a Tauri webview window's are. Mirrors
    # Tauri's <tt>WindowEvent::DragDrop(DragDropEvent)</tt>.
    DragDrop = Data.define(:event)

    # The system's theme changed; +theme+ is a Theme. Mirrors Tauri's
    # <tt>WindowEvent::ThemeChanged(Theme)</tt>.
    ThemeChanged = Data.define(:theme)
  end
end

# SPDX-SnippetEnd
