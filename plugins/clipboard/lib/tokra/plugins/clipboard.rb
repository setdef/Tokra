# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Plugin, commands, and ClipboardExt adapted from
#                      tauri-plugin-clipboard-manager src/lib.rs and src/commands.rs

require "tokra"

# The native extension. A failure to load it is a real installation problem
# (a missing or unloadable library), so its LoadError propagates as-is.
require "tokra_clipboard/tokra_clipboard"

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
      # This mirrors Tauri's ClipboardExt blanket implementation (lib.rs:32-41).
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
      # Arguments are checked the way Tauri deserializes them: a missing or
      # mistyped argument rejects with Tauri's message, for example
      # <tt>invalid args `text` for command `write_text`: command
      # write_text missing required key text</tt>.
      #
      # *Deviation*: Tauri runs these commands as +async+ functions, off the
      # main thread. Tokra dispatches every invoke on the main thread today,
      # so the Linux deadlock warning on read_text and read_image applies to
      # the IPC commands too. Moving dispatch to a worker Ractor (ADR 001)
      # lifts it.
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
        # stores it in managed state for ClipboardManagerExt access, the
        # body of Tauri's setup closure, which calls
        # <tt>app.manage(clipboard)</tt> (lib.rs:54-61). Construction at
        # registration matches Tauri's Plugin::initialize timing. Every
        # operation goes through the managed clipboard, so a second plugin
        # instance (whose manage call finds one already managed) shares the
        # first one's clipboard instead of opening another:
        #
        #   handle.plugin(Tokra::Plugins::Clipboard::Plugin.new(handle))
        def initialize(app, config = {})
          super
          native = TokraClipboard::Native::Clipboard.new
          Ractor.make_shareable(native)
          app.manage(native)
        end

        # Reads text from the clipboard.
        #
        # Returns the clipboard text content. An empty clipboard raises
        # Error::Clipboard carrying arboard's message, exactly as Tauri's
        # <tt>read_text</tt> propagates the error to a rejected promise.
        #
        # *Warning*: Do not call this on the main thread on Linux. The
        # underlying libraries may deadlock when reading data this app
        # copied, for example text the user copied from the WebView.
        #
        # === Example
        #
        #   plugin.read_text  #=> "copied text"
        def read_text
          clipboard.read_text
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Writes text to the clipboard.
        #
        # Raises Error::Clipboard when the write fails.
        #
        # +text+:: the text string to write
        #
        # === Example
        #
        #   plugin.write_text("Hello")
        def write_text(text)
          clipboard.write_text(text)
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Reads an image from the clipboard as a Tokra::Image.
        #
        # Mirrors Tauri's Clipboard#read_image (desktop.rs). An empty
        # clipboard raises Error::Clipboard.
        #
        # *Warning*: Do not call this on the main thread on Linux. The
        # underlying libraries may deadlock when reading data this app
        # copied.
        #
        # === Example
        #
        #   image = plugin.read_image
        #   File.binwrite("shot.rgba", image.rgba)
        def read_image
          Tokra::Image.new(*clipboard.read_image)
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Writes a Tokra::Image to the clipboard.
        #
        # Mirrors Tauri's Clipboard#write_image (desktop.rs). Raises
        # Error::Clipboard when the write fails, including when the image
        # is empty or its byte count does not match its dimensions.
        #
        # +image+:: the Tokra::Image to write
        #
        # === Example
        #
        #   plugin.write_image(Tokra::Image.from_path("icon.png"))
        def write_image(image)
          clipboard.write_image(image.rgba, image.width, image.height)
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
          clipboard.write_html(html, alt_text)
        rescue RuntimeError => e
          raise Error::Clipboard, e.message
        end

        # Clears the clipboard contents.
        #
        # Raises Error::Clipboard when the clear fails.
        #
        # === Example
        #
        #   plugin.clear
        def clear
          clipboard.clear
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

        # Cleans up the managed clipboard on exit, as arboard requires
        # before the process ends. Mirrors the on_event hook in Tauri's
        # clipboard-manager lib.rs (62-66), which cleans
        # <tt>app.clipboard()</tt>, the managed state.
        def on_event(app, event)
          return unless event.is_a?(Tokra::RunEvent::Exit)

          app.clipboard.cleanup
        end

        # The managed native clipboard (ClipboardExt, lib.rs:37-41).
        private def clipboard
          app.clipboard
        end

        private def handle_read_text(invoke)
          invoke.resolve(read_text)
          true
        end

        # Writes payload text. The mobile-only label is checked but unused,
        # as on Tauri desktop, which still deserializes it as an
        # Option<String> (commands.rs:9-18).
        private def handle_write_text(invoke)
          text = string_arg(invoke, "text")
          optional_string_arg(invoke, "label", expected: "a string")
          write_text(text)
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
          value = required_arg(invoke, "image")
          image = begin
            Tokra::JsImage.new(value).into_img(invoke.webview.resources_table)
          rescue ArgumentError => e
            raise ArgumentError, invalid_args(invoke, "image", e.message)
          end
          write_image(image)
          invoke.resolve(nil)
          true
        end

        # Writes HTML using the wire's camelCase altText key
        # (commands.rs:63-72; guest-js sends { html, altText }).
        private def handle_write_html(invoke)
          write_html(string_arg(invoke, "html"), optional_string_arg(invoke, "altText"))
          invoke.resolve(nil)
          true
        end

        # Clears the clipboard (commands.rs:74-80).
        private def handle_clear(invoke)
          clear
          invoke.resolve(nil)
          true
        end

        # A required argument, or ArgumentError with Tauri's missing-key
        # message (ipc/command.rs:97-102).
        private def required_arg(invoke, key)
          payload = invoke.payload
          unless payload.key?(key)
            raise ArgumentError,
              invalid_args(invoke, key, "command #{invoke.command} missing required key #{key}")
          end

          payload[key]
        end

        # A required string argument (a Rust &str).
        private def string_arg(invoke, key)
          value = required_arg(invoke, key)
          return value if value.is_a?(String)

          raise ArgumentError, invalid_args(invoke, key, invalid_type(value))
        end

        # An optional string argument (a Rust Option<&str>, or with
        # <tt>expected: "a string"</tt> an Option<String>): absent or null
        # is +nil+.
        private def optional_string_arg(invoke, key, expected: "a borrowed string")
          value = invoke.payload[key]
          return value if value.nil? || value.is_a?(String)

          raise ArgumentError, invalid_args(invoke, key, invalid_type(value, expected))
        end

        # Tauri's InvalidArgs message (tauri error.rs:59-60).
        private def invalid_args(invoke, key, reason)
          "invalid args `#{key}` for command `#{invoke.command}`: #{reason}"
        end

        # serde_json's message for a JSON value where a string was
        # expected: serde's &str visitor expects "a borrowed string", its
        # String visitor "a string".
        private def invalid_type(value, expected = "a borrowed string")
          unexpected = case value
          when nil then "null"
          when true, false then "boolean `#{value}`"
          when Integer then "integer `#{value}`"
          when Float then "floating point `#{value}`"
          when Array then "sequence"
          else "map"
          end
          "invalid type: #{unexpected}, expected #{expected}"
        end
      end
    end
  end
end

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Clipboard::ClipboardManagerExt)

# SPDX-SnippetEnd
