# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: CloseRequestApi adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Keeps a window open when someone asks to close it.
  #
  # A click on the close button, or Window#close, asks first: Tokra emits
  # WindowEvent::CloseRequested carrying one of these to your
  # Builder#on_window_event listeners, then to plugins and the App#run
  # callback. Call #prevent_close to keep the window, say to ask about
  # unsaved work or to hide it to the tray instead. Otherwise the window
  # closes once every handler has returned. Window#destroy skips the
  # question.
  #
  # Tokra reads the answer once, as soon as every handler has returned.
  # Calling #prevent_close later does nothing.
  #
  # Mirrors Tauri's <tt>CloseRequestApi</tt> (app.rs:94-103), whose answer
  # the runtime reads right after the callback (tauri-runtime-wry
  # lib.rs:4262-4290).
  #
  # === Example
  #
  #   Tokra::Builder.default.on_window_event(&Ractor.shareable_proc { |_window, event|
  #     event.api.prevent_close if event.is_a?(Tokra::WindowEvent::CloseRequested)
  #   })
  class CloseRequestApi
    # Creates the API for one close request. Tokra creates it; you receive
    # it on the event.
    def initialize # :nodoc:
      @prevented = false
    end

    # Prevents the window from being closed.
    #
    # Mirrors Tauri's <tt>CloseRequestApi::prevent_close</tt>
    # (app.rs:98-103).
    #
    # === Example
    #
    #   event.api.prevent_close
    def prevent_close
      @prevented = true
      nil
    end

    # Whether a handler called #prevent_close. Tokra asks once every
    # handler has returned.
    #
    # === Example
    #
    #   api.prevented?  #=> false
    def prevented?
      @prevented
    end
  end
end

# SPDX-SnippetEnd
