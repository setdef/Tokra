# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Plugin, commands, Clipboard, and ClipboardExt adapted
#                      from tauri-plugin-clipboard-manager src/lib.rs,
#                      src/commands.rs, and src/desktop.rs

require "tokra"

# The system clipboard, through arboard (ADR 011). A failure to load it is a
# real installation problem (a missing or unloadable library), so its
# LoadError propagates as-is.
require "ferro/arboard"

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
        # (error.rs), which every arboard error converts into. Tokra turns
        # each Ferro::Arboard::Error subclass into it the same way, keeping
        # arboard's message.
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
        # Returns the Clipboard from managed state.
        def clipboard
          state(Clipboard)
        end
      end

      # The clipboard an app shares through managed state.
      #
      # An app reads and writes the clipboard from many places: IPC commands,
      # setup hooks, menu handlers, perhaps other Ractors. Each opening its
      # own system clipboard would scatter the failures, and on Linux the
      # copied contents live only as long as some clipboard in the process
      # stays open.
      #
      # The plugin builds one Clipboard at registration and manages it, so
      # every manager reaches it as +clipboard+. Each method raises
      # Error::Clipboard with arboard's message when the system clipboard
      # refuses, exactly as Tauri's methods return
      # <tt>Error::Clipboard(String)</tt>.
      #
      # A Clipboard is frozen and Ractor-shareable as built (ADR 007): it
      # holds a frozen Ferro::Arboard::Clipboard, which takes calls from any
      # thread or Ractor.
      #
      # Mirrors Tauri's <tt>Clipboard</tt> (desktop.rs:11-123).
      #
      # === Example
      #
      #   handle.clipboard.write_text("Hello")
      #   handle.clipboard.read_text  #=> "Hello"
      class Clipboard
        # Opens the system clipboard.
        #
        # A system without a clipboard does not stop the app from booting:
        # the failure is kept, and every method raises it as
        # Error::Clipboard, as Tauri's <tt>init</tt> stores arboard's error
        # (desktop.rs:11-19).
        def initialize
          @clipboard, @error = begin
            [Ferro::Arboard::Clipboard.new, nil]
          rescue Ferro::Arboard::Error => e
            [nil, e.message]
          end
          # Tauri keeps arboard's clipboard in an Option so its exit hook
          # can drop it. A frozen object cannot drop a reference or flip a
          # flag, so a Ractor::Port, shareable yet closable once, marks the
          # clipboard retired. Ruby frees arboard's clipboard itself at exit.
          @live = Ractor::Port.new
          Ractor.make_shareable(self)
        end

        # Writes text to the clipboard (desktop.rs:31-42).
        #
        # === Example
        #
        #   clipboard.write_text("Hello")
        def write_text(text)
          with_clipboard { |clipboard| clipboard.set_text(text) }
        end

        # Writes a Tokra::Image to the clipboard (desktop.rs:44-59).
        #
        # An image with a zero width or height, or with a byte count other
        # than <tt>width * height * 4</tt>, raises Error::Clipboard with
        # arboard's ConversionFailure message.
        #
        # === Example
        #
        #   clipboard.write_image(Tokra::Image.from_path("icon.png"))
        def write_image(image)
          bytes = Ferro::Arboard::ImageData.new(width: image.width, height: image.height, bytes: image.rgba)
          with_clipboard { |clipboard| clipboard.set_image(bytes) }
        end

        # Reads text from the clipboard (desktop.rs:61-70). An empty
        # clipboard raises Error::Clipboard.
        #
        # *Warning*: Do not call this on the main thread on Linux. The
        # underlying libraries may deadlock when reading data this app
        # copied, for example text the user copied from the WebView.
        #
        # === Example
        #
        #   clipboard.read_text  #=> "copied text"
        def read_text
          with_clipboard(&:get_text)
        end

        # Writes HTML, with +alt_text+ as the plain-text flavor when given
        # (desktop.rs:72-87).
        #
        # === Example
        #
        #   clipboard.write_html("<b>Hi</b>", "Hi")
        def write_html(html, alt_text = nil)
          with_clipboard { |clipboard| clipboard.set_html(html, alt_text) }
        end

        # Clears the clipboard (desktop.rs:89-100).
        #
        # On X11, text written right after a clear, from any clipboard in
        # the process, can vanish: arboard drops the process's data when the
        # X server's late reply to the clear arrives (arboard 3.7.0
        # src/platform/linux/x11.rs:233-242). Tauri shares the race.
        #
        # === Example
        #
        #   clipboard.clear
        def clear
          with_clipboard(&:clear)
        end

        # Reads an image from the clipboard as a Tokra::Image
        # (desktop.rs:102-116). An empty clipboard raises Error::Clipboard.
        #
        # *Warning*: Do not call this on the main thread on Linux. The
        # underlying libraries may deadlock when reading data this app
        # copied.
        #
        # === Example
        #
        #   clipboard.read_image.width  #=> 640
        def read_image
          image = with_clipboard(&:get_image)
          Tokra::Image.new(rgba: image.bytes, width: image.width, height: image.height)
        end

        # Retires the clipboard; the plugin calls this when the app exits
        # (desktop.rs:118-122). Every later call raises Error::Clipboard
        # with "Clipboard has been cleaned up".
        #
        # *Deviation*: Tauri drops arboard's clipboard here and panics on a
        # later call. Ruby cannot drop an object on demand, so arboard's
        # clipboard goes when Ruby frees it, at the latest when the process
        # exits; a later call raises instead of ending the VM.
        def cleanup
          @live.close
          nil
        end

        # Runs the block on the open clipboard, in Tauri's order: a failed
        # open reports its own error first (desktop.rs:33-39).
        private def with_clipboard
          raise Error::Clipboard, @error if @error
          raise Error::Clipboard, "Clipboard has been cleaned up" if @live.closed?

          yield @clipboard
        rescue Ferro::Arboard::Error => e
          raise Error::Clipboard, e.message
        end
      end

      # Clipboard plugin for Tokra desktop applications.
      #
      # Provides read/write access to the system clipboard through
      # ferro-arboard, a one-to-one Ruby binding of the arboard crate. The
      # managed Clipboard is Ractor-shareable (ADR 007).
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
        # Creates the Ractor-shareable Clipboard (ADR 007) and stores it in
        # managed state for ClipboardManagerExt access, the
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
          app.manage(Clipboard.new)
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
          clipboard.read_image
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
          clipboard.write_image(image)
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
        end

        # Handles IPC invoke commands from the JavaScript frontend.
        #
        # The router strips the <tt>plugin:clipboard-manager|</tt> prefix,
        # so this matches bare command names. Failures reject the invoke
        # with the error message, mirroring Tauri's Result-to-InvokeError
        # propagation (commands.rs), as does an argument that does not
        # read. Anything else is a bug, and reaches the router.
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
          Tokra::Error::InvalidArgs,
          Tokra::Error::Io => e

          invoke.reject(e.message)
          true
        end

        # Cleans up the managed clipboard on exit. Mirrors the on_event hook in Tauri's
        # clipboard-manager lib.rs (62-66), which cleans
        # <tt>app.clipboard()</tt>, the managed state.
        def on_event(app, event)
          return unless event.is_a?(Tokra::RunEvent::Exit)

          app.clipboard.cleanup
        end

        # The managed Clipboard (ClipboardExt, lib.rs:37-41).
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

        # Reads the JsImage argument, resolves it against the calling
        # webview's resource table, and writes it (commands.rs:43-50): a
        # payload of the wrong shape is the argument's InvalidArgs, and one
        # that names no image is into_img's error.
        private def handle_write_image(invoke)
          js_image = argument(invoke, "image").deserialize { |value| Tokra::JsImage.deserialize(value) }
          write_image(js_image.into_img(invoke.webview.resources_table))
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

        # Argument +key+ of +invoke+, read as Tauri's CommandItem reads it.
        private def argument(invoke, key)
          Tokra::Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
        end

        # A required string argument (a Rust &str), or InvalidArgs.
        private def string_arg(invoke, key)
          argument(invoke, key).deserialize { |value| string_value(value, "a borrowed string") }
        end

        # An optional string argument (a Rust Option<&str>, or with
        # <tt>expected: "a string"</tt> an Option<String>): absent or null
        # is +nil+.
        private def optional_string_arg(invoke, key, expected: "a borrowed string")
          argument(invoke, key).deserialize_option { |value| string_value(value, expected) }
        end

        # +value+ if it is a String, or serde's error naming +expected+:
        # serde's &str visitor expects "a borrowed string", its String
        # visitor "a string".
        private def string_value(value, expected)
          value.is_a?(String) ? value : raise(Tokra::Ipc::CommandItem::Mismatch.invalid_type(value, expected))
        end
      end
    end
  end
end

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Clipboard::ClipboardManagerExt)

# SPDX-SnippetEnd
