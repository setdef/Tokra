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

    # Event loop is exiting.
    Exit = Data.define

    # The app is about to exit. +code+ is +nil+ when the last window
    # closed, and an Integer when code asked through AppHandle#exit.
    # Call <tt>api.prevent_exit</tt>, an ExitRequestApi, to keep the app
    # running. Signals (Ctrl-C, +SIGTERM+) end the app without asking.
    # Mirrors Tauri's <tt>RunEvent::ExitRequested { code, api }</tt>
    # (app.rs:200-207).
    ExitRequested = Data.define(:code, :api)

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
