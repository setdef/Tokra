# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: RESTART_EXIT_CODE and ExitRequestApi adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # The exit code on RunEvent::ExitRequested when the app asks to restart.
  # ExitRequestApi#prevent_exit does nothing for it.
  #
  # Mirrors Tauri's <tt>RESTART_EXIT_CODE</tt>, <tt>i32::MAX</tt>
  # (app.rs:73-74).
  RESTART_EXIT_CODE = 2_147_483_647

  # Keeps your app running when it is about to exit.
  #
  # A desktop app ends when its last window closes, or when code calls
  # AppHandle#exit. Some apps should outlive their windows: a tray app, a
  # menu bar utility, an app that finishes a sync first. Before Tokra ends
  # the app it emits RunEvent::ExitRequested carrying one of these, and a
  # plugin or the App#run callback that calls #prevent_exit keeps it
  # running. With no windows left, a later AppHandle#exit ends it.
  #
  # Tokra reads the answer once, as soon as every handler has returned.
  # Calling #prevent_exit later, from a thread the handler started, does
  # nothing.
  #
  # Mirrors Tauri's <tt>ExitRequestApi</tt> (app.rs:76-92), whose answer
  # the runtime reads right after the callback (tauri-runtime-wry
  # lib.rs:4177-4185, 4216-4227).
  #
  # === Example
  #
  #   app.run do |_handle, event|
  #     event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested) && event.code.nil?
  #   end
  class ExitRequestApi
    # Creates the API for an exit request with +code+, +nil+ when the last
    # window closed. Tokra creates it; you receive it on the event.
    def initialize(code) # :nodoc:
      @code = code
      @prevented = false
    end

    # Prevents the app from exiting.
    #
    # This is ignored when the code is RESTART_EXIT_CODE, so a restart
    # cannot be refused.
    #
    # Mirrors Tauri's <tt>ExitRequestApi::prevent_exit</tt>
    # (app.rs:83-92).
    #
    # === Example
    #
    #   event.api.prevent_exit
    def prevent_exit
      @prevented = true unless @code == RESTART_EXIT_CODE
      nil
    end

    # Whether a handler called #prevent_exit. Tokra asks once every
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
