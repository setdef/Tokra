# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Error adapted from tauri-plugin-global-shortcut src/error.rs

module Tokra
  module Plugins
    module GlobalShortcut
      # Base error for global shortcut operations.
      #
      # Registering a shortcut can fail several ways: the text names no
      # key, another program holds the combination, the system has no code
      # for the key, or the event loop has ended and the main thread can
      # no longer take the call. Your code wants to rescue them all in one
      # place and show the user a clear reason.
      #
      # Every method of GlobalShortcut and Builder raises a subclass of
      # this error, with Tauri's message, and a command rejects with the
      # same message.
      #
      # Mirrors the plugin's <tt>Error</tt> (error.rs:7-16), which
      # serializes as its message (error.rs:18-25).
      #
      # === Example
      #
      #   begin
      #     handle.global_shortcut.register("CmdOrCtrl+Shift+K")
      #   rescue Tokra::Plugins::GlobalShortcut::Error => e
      #     warn "No shortcut: #{e.message}"
      #   end
      class Error < Tokra::Error
        # global-hotkey refused: the shortcut does not parse, or the system
        # will not register or unregister it. The message is global-hotkey's
        # own, such as <tt>Unable to register hotkey: ...</tt>. Mirrors
        # <tt>Error::GlobalHotkey(String)</tt>, which every global-hotkey
        # error and parse error converts into (error.rs:27-37).
        class GlobalHotkey < Error; end

        # The event loop ended before the main thread answered, as Rust's
        # <tt>RecvError</tt> reports a channel closed unanswered. Mirrors
        # <tt>Error::RecvError</tt> (error.rs:12-13).
        class RecvError < Error
          # Rust's text for a closed channel (std::sync::mpsc::RecvError).
          MESSAGE = "receiving on a closed channel"

          # Creates the error with Rust's message.
          def initialize(message = MESSAGE)
            super
          end
        end

        # Tokra could not send the call to the main thread, because the
        # event loop has ended. The message is Tokra::Error::Runtime's.
        # Mirrors <tt>Error::Tauri(tauri::Error)</tt> (error.rs:14-15).
        class Tauri < Error; end
      end
    end
  end
end

# SPDX-SnippetEnd
