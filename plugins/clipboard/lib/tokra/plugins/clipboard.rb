# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tokra"

# Load native extension
begin
  require "tokra_clipboard/tokra_clipboard"
rescue LoadError
  # Extension not compiled yet
end

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
    # Namespace for the clipboard plugin.
    #
    # Use Tokra::Plugins::Clipboard::Plugin as the plugin class.
    module Clipboard
      # Base error for clipboard operations.
      class Error < Tokra::Error; end

      # Raised when another application holds the clipboard lock.
      #
      # Platform-specific behavior:
      # - Windows: Raised after 5 retry attempts (5ms spacing)
      # - X11: Raised when set_selection_owner() fails (rare)
      # - macOS: Never raised (arboard uses pasteboard, no locking)
      class ClipboardOccupiedError < Error; end

      # Raised when clipboard content is unavailable or incompatible.
      class ClipboardUnavailableError < Error; end

      # Manager extension mixin module providing clipboard() accessor.
      #
      # When included into Tokra::Manager, provides direct clipboard access:
      #
      #   app_handle.clipboard.read_text
      #   window.clipboard.write_text("Hello")
      #
      # This mirrors Tauri's ClipboardExt blanket implementation.
      module ClipboardManagerExt
        # Returns the clipboard instance from managed state.
        def clipboard
          state(TokraClipboard::Native::Clipboard)
        end
      end

      # Clipboard plugin for Tokra desktop applications.
      #
      # Provides read/write access to the system clipboard using the arboard crate.
      # Uses Rust Mutex for thread-safe, Ractor-shareable clipboard access per ADR-007.
      #
      # == JavaScript API (Tauri Compatibility)
      #
      # The following IPC commands are exposed for frontend use:
      #
      #   // Write text to clipboard
      #   await invoke("plugin:clipboard-manager|write_text", { text: "Hello" });
      #
      #   // Read text from clipboard (rejects when the clipboard is empty)
      #   const text = await invoke("plugin:clipboard-manager|read_text");
      #
      #   // Clear clipboard
      #   await invoke("plugin:clipboard-manager|clear");
      #
      # == Ruby API
      #
      #   Tokra::Builder.new
      #     .plugin(Tokra::Plugins::Clipboard::Plugin.new)
      #     .run
      #
      class Plugin < Tokra::Plugin
        # Returns the unique plugin identifier.
        #
        # Uses "clipboard-manager" for 1:1 compatibility with Tauri's
        # guest-js/index.ts command naming.
        def name
          "clipboard-manager"
        end

        # Initializes the clipboard plugin.
        #
        # Creates Ractor-shareable native clipboard per ADR-007.
        # The Rust Mutex enables interior mutability on the frozen object.
        def initialize
          @native = TokraClipboard::Native::Clipboard.new
          Ractor.make_shareable(@native)
        end

        # Called when plugin is registered with the app.
        #
        # Stores native clipboard in managed state for ClipboardManagerExt access.
        def on_register(app)
          app.manage(@native)
        end

        # Reads text from the clipboard.
        #
        # Returns the clipboard text content. An empty clipboard raises a
        # RuntimeError carrying arboard's message, exactly as Tauri's
        # <tt>read_text</tt> propagates the error to a rejected promise.
        #
        # *Warning*: Do not call this on the main thread on Linux — the
        # underlying libraries may deadlock when reading data this app
        # copied, for example text the user copied from the WebView.
        def read_text
          @native.read_text
        end

        # Writes text to the clipboard.
        #
        # +text+:: the text string to write
        def write_text(text)
          @native.write_text(text)
        end

        # Clears the clipboard contents.
        def clear
          @native.clear
        end

        # Handles IPC invoke commands from JavaScript frontend.
        #
        # Returns +true+ if this plugin handled the command, +false+ otherwise.
        def extend_api(invoke)
          case invoke.command
          when "plugin:clipboard-manager|read_text"
            invoke.resolve(read_text)
            true
          when "plugin:clipboard-manager|write_text"
            write_text(invoke.payload["text"])
            invoke.resolve(nil)
            true
          when "plugin:clipboard-manager|clear"
            clear
            invoke.resolve(nil)
            true
          else
            false
          end
        end

        # Called on each run loop event.
        #
        # Handles RunEvent::Exit to cleanup native clipboard resources.
        def on_event(event)
          return unless event.is_a?(Tokra::RunEvent::Exit)

          @native.cleanup
        end
      end
    end
  end
end

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Clipboard::ClipboardManagerExt)
