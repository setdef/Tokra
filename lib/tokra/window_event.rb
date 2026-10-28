# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WindowEvent adapted from tauri/crates/tauri/src/window/mod.rs

module Tokra
  # Window event types dispatched to on_window_event callbacks.
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

    # Window focus changed. +focused+ is true if gained focus.
    Focused = Data.define(:focused)

    # Window was moved to position (+x+, +y+).
    Moved = Data.define(:x, :y)

    # Window was resized to (+width+, +height+).
    Resized = Data.define(:width, :height)

    # Display scale factor changed.
    ScaleFactorChanged = Data.define(:scale_factor)

    # System theme changed (light/dark).
    ThemeChanged = Data.define(:theme)
  end
end

# SPDX-SnippetEnd
