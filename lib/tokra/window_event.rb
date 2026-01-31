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
    # Window close was requested by user.
    CloseRequested = Data.define

    # Window was destroyed.
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
