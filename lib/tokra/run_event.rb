# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: RunEvent structure adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Run event types dispatched during App#run.
  #
  # These mirror Tauri's RunEvent enum variants.
  module RunEvent
    # Emitted when the event loop is about to start.
    Ready = Data.define

    # Emitted after the event loop exits.
    Exit = Data.define

    # Emitted when an exit is requested but not yet confirmed.
    ExitRequested = Data.define(:code)

    # Emitted when a window event occurs.
    WindowEvent = Data.define(:label, :event)

    # Emitted when a webview event occurs.
    WebviewEvent = Data.define(:label, :event)

    # Emitted when the app is resumed (mobile).
    Resumed = Data.define

    # Emitted when main events are cleared.
    MainEventsCleared = Data.define
  end
end

# SPDX-SnippetEnd
