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
      #
      # Mirrors the error type of Tauri's clipboard-manager plugin.
      class Error < Tokra::Error
        # Raised when any clipboard operation fails.
        #
        # A clipboard read or write can fail many ways: the clipboard is
        # empty, another process holds it, or the platform refuses the
        # format. Tauri collapses every one of these into a single error
        # variant carrying the underlying message, and so does Tokra.
        #
        # Mirrors <tt>tauri_plugin_clipboard_manager::Error::Clipboard(String)</tt>
        # (error.rs), which every arboard error converts into.
        #
        # === Example
        #
        #   begin
        #     plugin.read_text
        #   rescue Tokra::Plugins::Clipboard::Error::Clipboard => e
        #     puts e.message  # e.g. "The clipboard contents were not available..."
        #   end
        class Clipboard < Error; end
      end

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
      #   // Read an image; resolves a resource ID for the Image API
      #   const rid = await invoke("plugin:clipboard-manager|read_image");
      #
      #   // Write an image by resource ID, byte array, path, or RGBA hash
      #   await invoke("plugin:clipboard-manager|write_image", { image: rid });
      #
      #   // Write HTML with a plain-text fallback
      #   await invoke("plugin:clipboard-manager|write_html", { html: "<b>Hi</b>", altText: "Hi" });
      #
      #   // Clear clipboard
      #   await invoke("plugin:clipboard-manager|clear");
      #
      # == Ruby API
      #
      # Register the plugin with the app handle once the app exists, for
      # example from the setup hook:
      #
      #   Tokra::Builder.new
      #     .setup { |app| app.handle.plugin(Tokra::Plugins::Clipboard::Plugin.new(app.handle)) }
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

        # Initializes the plugin with the app handle and configuration.
        #
        # Creates the Ractor-shareable native clipboard (ADR-007) and
        # stores it in managed state for ClipboardManagerExt access — the
        # body of Tauri's setup closure, which calls
        # <tt>app.manage(clipboard)</tt> (clipboard-manager lib.rs).
        # Construction at registration matches Tauri's Plugin::initialize
        # timing:
        #
        #   handle.plugin(Tokra::Plugins::Clipboard::Plugin.new(handle))
        def initialize(app, config = {})
          super
          @native = TokraClipboard::Native::Clipboard.new
          Ractor.make_shareable(@native)
          app.manage(@native)
        end

        # Reads text from the clipboard.
        #
        # Returns the clipboard text content. An empty clipboard raises
        # Error::Clipboard carrying arboard's message, exactly as Tauri's
        # <tt>read_text</tt> propagates the error to a rejected promise.
        #
        # *Warning*: Do not call this on the main thread on Linux — the
        # underlying libraries may deadlock when reading data this app
        # copied, for example text the user copied from the WebView.
        def read_text
          @native.read_text
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Writes text to the clipboard.
        #
        # Raises Error::Clipboard when the write fails.
        #
        # +text+:: the text string to write
        def write_text(text)
          @native.write_text(text)
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Reads an image from the clipboard as a Tokra::Image.
        #
        # Mirrors Tauri's Clipboard#read_image (desktop.rs). An empty
        # clipboard raises Error::Clipboard.
        #
        # *Warning*: Do not call this on the main thread on Linux — the
        # underlying libraries may deadlock when reading data this app
        # copied.
        #
        # === Example
        #
        #   image = plugin.read_image
        #   File.binwrite("shot.rgba", image.rgba)
        def read_image
          Tokra::Image.new(*@native.read_image)
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Writes a Tokra::Image to the clipboard.
        #
        # Mirrors Tauri's Clipboard#write_image (desktop.rs). Raises
        # Error::Clipboard when the write fails, including when the image's
        # byte count does not match its dimensions.
        #
        # +image+:: the Tokra::Image to write
        #
        # === Example
        #
        #   plugin.write_image(Tokra::Image.from_path("icon.png"))
        def write_image(image)
          @native.write_image(image.rgba, image.width, image.height)
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Writes HTML to the clipboard.
        #
        # Mirrors Tauri's Clipboard#write_html (desktop.rs). +alt_text+,
        # when given, becomes the plain-text flavor that non-HTML
        # consumers read. Raises Error::Clipboard when the write fails.
        #
        # === Example
        #
        #   plugin.write_html("<b>Hi</b>", "Hi")
        def write_html(html, alt_text = nil)
          @native.write_html(html, alt_text)
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Clears the clipboard contents.
        #
        # Raises Error::Clipboard when the clear fails.
        def clear
          @native.clear
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Handles IPC invoke commands from the JavaScript frontend.
        #
        # The router strips the <tt>plugin:clipboard-manager|</tt> prefix,
        # so this matches bare command names. Failures reject the invoke
        # with the error message, mirroring Tauri's Result-to-InvokeError
        # propagation (commands.rs).
        #
        # Returns +true+ if this plugin handled the command, +false+ otherwise.
        def extend_api(invoke)
          case invoke.command
          when "read_text" then handle_read_text(invoke)
          when "write_text" then handle_write_text(invoke)
          when "read_image" then handle_read_image(invoke)
          when "write_image" then handle_write_image(invoke)
          when "write_html" then handle_write_html(invoke)
          when "clear" then handle_clear(invoke)
          else false
          end
        rescue Error,
          Tokra::Error::BadResourceId,
          Tokra::Error::Image,
          ArgumentError,
          SystemCallError => e

          invoke.reject(e.message)
          true
        end

        # Cleans up the native clipboard on exit, as arboard requires
        # before the process ends. Mirrors the on_event hook in Tauri's
        # clipboard-manager lib.rs.
        def on_event(_app, event)
          return unless event.is_a?(Tokra::RunEvent::Exit)

          @native.cleanup
        end

        private def handle_read_text(invoke)
          invoke.resolve(read_text)
          true
        end

        # Writes payload text; the mobile-only label key is ignored, as
        # on Tauri desktop (commands.rs:10-18).
        private def handle_write_text(invoke)
          write_text(invoke.payload["text"])
          invoke.resolve(nil)
          true
        end

        # Stores the clipboard image in the calling webview's resource
        # table and resolves its resource ID (commands.rs:53-61).
        private def handle_read_image(invoke)
          rid = invoke.webview.resources_table.add(read_image)
          invoke.resolve(rid)
          true
        end

        # Resolves the JsImage payload against the calling webview's
        # resource table and writes it (commands.rs:43-50).
        private def handle_write_image(invoke)
          image = Tokra::JsImage.new(invoke.payload["image"])
            .into_img(invoke.webview.resources_table)
          write_image(image)
          invoke.resolve(nil)
          true
        end

        # Writes HTML using the wire's camelCase altText key
        # (commands.rs:64-72; guest-js sends { html, altText }).
        private def handle_write_html(invoke)
          write_html(invoke.payload["html"], invoke.payload["altText"])
          invoke.resolve(nil)
          true
        end

        # Clears the clipboard (commands.rs:74-80).
        private def handle_clear(invoke)
          clear
          invoke.resolve(nil)
          true
        end
      end
    end
  end
end

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Clipboard::ClipboardManagerExt)
