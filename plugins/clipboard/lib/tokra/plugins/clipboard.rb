# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: init, Commands, Clipboard, and ClipboardExt adapted
#                      from tauri-plugin-clipboard-manager src/lib.rs,
#                      src/commands.rs, and src/desktop.rs

require "tokra"

# The system clipboard, through arboard (ADR 020). A failure to load it is a
# real installation problem (a missing or unloadable library), so its
# LoadError propagates as-is.
require "ferro/arboard"

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
    # The system clipboard for Tokra desktop applications.
    #
    # A desktop app copies and pastes: a link to share, a result to paste
    # elsewhere, an image the user copied from another app. The page cannot
    # reach the system clipboard on its own, and each part of the app
    # opening the clipboard for itself scatters the failures.
    #
    # This plugin opens it once, through ferro-arboard, a one-to-one Ruby
    # binding of the arboard crate, manages it as a Clipboard every manager
    # reaches as +clipboard+, and serves the commands of Tauri's
    # clipboard-manager plugin, so the frontend uses
    # <tt>@tauri-apps/plugin-clipboard-manager</tt> unchanged. The managed
    # Clipboard is Ractor-shareable (doc/contributors/design/plugins.md,
    # "State shared across Ractors").
    #
    # Use it to read and write text, HTML, and images, from Ruby or from
    # the page.
    #
    # == JavaScript API (Tauri Compatibility)
    #
    #   import { writeText, readText, writeHtml, readImage, writeImage, clear }
    #     from '@tauri-apps/plugin-clipboard-manager';
    #
    #   await writeText('Hello');
    #   const text = await readText();             // rejects when the clipboard is empty
    #   await writeHtml('<b>Hi</b>', 'Hi');          // with a plain-text fallback
    #   const image = await readImage();           // an Image, by resource ID
    #   await writeImage(image);                   // an Image, bytes, a path, or RGBA
    #   await clear();
    #
    # Arguments are checked the way Tauri deserializes them: a missing or
    # mistyped argument rejects with Tauri's message, for example
    # <tt>invalid args `text` for command `write_text`: command
    # write_text missing required key text</tt>.
    #
    # With <tt>app.withGlobalTauri</tt> in your config, a page with no
    # bundler finds the same functions on
    # <tt>window.__TAURI__.clipboardManager</tt>: the plugin ships Tauri's
    # own <tt>api-iife.js</tt>, which every page runs after Tauri's bundle.
    # Require <tt>tokra-clipboard</tt> before Tokra.generate_context reads
    # it.
    #
    # == Ruby API
    #
    # Register the plugin on the builder with ::init:
    #
    #   require "tokra-clipboard"
    #
    #   Tokra::Builder.default
    #     .plugin(Tokra::Plugins::Clipboard.init)
    #     .run(Tokra.generate_context)
    #
    #   handle.clipboard.write_text("Hello")
    #   handle.clipboard.read_text  #=> "Hello"
    #
    # The plugin takes no config: a non-null
    # <tt>plugins.clipboard-manager</tt> in your config fails the app with
    # Error::PluginInitialization, as Tauri's does.
    #
    # Mirrors Tauri's clipboard-manager plugin (lib.rs:43-69).
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
      # The plugin's setup builds one Clipboard and manages it, so every
      # manager reaches it as +clipboard+. Each method raises
      # Error::Clipboard with arboard's message when the system clipboard
      # refuses, exactly as Tauri's methods return
      # <tt>Error::Clipboard(String)</tt>.
      #
      # A Clipboard is frozen and Ractor-shareable as built
      # (doc/contributors/design/plugins.md, "State shared across Ractors"): it holds a
      # frozen Ferro::Arboard::Clipboard, which takes calls from any thread
      # or Ractor.
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
        # An image with a zero width or height raises Error::Clipboard with
        # arboard's ConversionFailure message, as does a byte count other
        # than <tt>width * height * 4</tt>, except on macOS, where
        # ferro-arboard hands arboard a longer buffer and arboard draws its
        # first <tt>width * height * 4</tt> bytes. A shorter or empty buffer,
        # or a size that overflows, still raises there.
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

      # The commands the plugin answers (build.rs:5-12).
      COMMANDS = %w[write_text read_text write_image read_image write_html clear].freeze

      # Initializes the plugin: a Tokra::Plugin::TauriPlugin named
      # +clipboard-manager+, the name in
      # <tt>plugin:clipboard-manager|read_text</tt>, for Tokra::Builder#plugin.
      #
      # Its setup opens the system clipboard and manages it as a Clipboard
      # for the app (a second plugin finds one already managed and shares
      # it). Each command answers from that managed Clipboard, rejecting
      # with Error::Clipboard's message or Tauri's argument error; any other
      # command is left for the router, and anything else a command raises
      # is a bug, and reaches the router. When the app exits, its
      # RunEvent::Exit retires the managed Clipboard.
      #
      # Mirrors Tauri's <tt>init</tt> (lib.rs:43-69).
      #
      # === Example
      #
      #   Tokra::Builder.default.plugin(Tokra::Plugins::Clipboard.init)
      def self.init
        Tokra::Plugin::Builder.new("clipboard-manager")
          .invoke_handler { |invoke| handle_invoke(invoke) }
          .setup { |app, _api| app.manage(Clipboard.new) }
          .on_event { |app, event| app.clipboard.cleanup if event.is_a?(Tokra::RunEvent::Exit) }
          .build
      end

      # Runs one of COMMANDS against the Clipboard the invoking webview's
      # app manages, as Tauri's commands take it as State; answers whether
      # it was one of them. Failures reject the invoke with the error's
      # message, mirroring Tauri's Result-to-InvokeError propagation
      # (commands.rs), as does an argument that does not read.
      def self.handle_invoke(invoke) # :nodoc:
        command = invoke.command
        return false unless COMMANDS.include?(command)

        clipboard = invoke.webview.app_handle.clipboard
        case command
        when "write_text" then Commands.write_text(invoke, clipboard)
        when "read_text" then Commands.read_text(invoke, clipboard)
        when "write_image" then Commands.write_image(invoke, clipboard)
        when "read_image" then Commands.read_image(invoke, clipboard)
        when "write_html" then Commands.write_html(invoke, clipboard)
        else Commands.clear(invoke, clipboard)
        end
        true
      rescue Error,
        Tokra::Error::BadResourceId,
        Tokra::Error::Image,
        Tokra::Error::InvalidArgs,
        Tokra::Error::Io => e

        invoke.reject(e.message)
        true
      end
      private_class_method :handle_invoke

      # The plugin's commands, each reading its arguments as Tauri
      # deserializes them, in order, and answering +invoke+ from
      # +clipboard+, the app's managed Clipboard. A failure raises for the
      # plugin's router to reject.
      #
      # *Deviation*: Tauri runs these commands as +async+ functions, off the
      # main thread. Tokra dispatches every invoke on the main thread today,
      # so the Linux deadlock warning on Clipboard#read_text and
      # Clipboard#read_image applies to the commands too. Answering them
      # off the main thread, as ADR 021 decides, lifts it.
      #
      # Mirrors Tauri's <tt>commands.rs</tt>.
      module Commands
        # Writes the payload's +text+. The mobile-only +label+ is checked but
        # unused, as on Tauri desktop, which still deserializes it as an
        # <tt>Option<String></tt> (commands.rs:9-18).
        def self.write_text(invoke, clipboard)
          text = string_arg(invoke, "text")
          optional_string_arg(invoke, "label", expected: "a string")
          clipboard.write_text(text)
          invoke.resolve(nil)
        end

        # Resolves the clipboard's text; an empty clipboard raises
        # Error::Clipboard (commands.rs:34-40).
        def self.read_text(invoke, clipboard)
          invoke.resolve(clipboard.read_text)
        end

        # Reads the JsImage argument, resolves it against the calling
        # webview's resource table, and writes it (commands.rs:42-51): a
        # payload of the wrong shape is the argument's InvalidArgs, and one
        # that names no image is +into_img+'s error.
        def self.write_image(invoke, clipboard)
          js_image = argument(invoke, "image").deserialize { |value| Tokra::JsImage.deserialize(value) }
          clipboard.write_image(js_image.into_img(invoke.webview.resources_table))
          invoke.resolve(nil)
        end

        # Stores the clipboard's image in the calling webview's resource
        # table and resolves its resource ID (commands.rs:53-62).
        def self.read_image(invoke, clipboard)
          invoke.resolve(invoke.webview.resources_table.add(clipboard.read_image))
        end

        # Writes the payload's +html+, with the wire's camelCase +altText+ as
        # the plain-text flavor (commands.rs:64-72; guest-js sends
        # <tt>{ html, altText }</tt>).
        def self.write_html(invoke, clipboard)
          clipboard.write_html(string_arg(invoke, "html"), optional_string_arg(invoke, "altText"))
          invoke.resolve(nil)
        end

        # Clears the clipboard (commands.rs:74-80).
        def self.clear(invoke, clipboard)
          clipboard.clear
          invoke.resolve(nil)
        end

        # Argument +key+ of +invoke+, read as Tauri's CommandItem reads it.
        def self.argument(invoke, key) # :nodoc:
          Tokra::Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
        end

        # A required string argument (a Rust &str), or InvalidArgs.
        def self.string_arg(invoke, key) # :nodoc:
          argument(invoke, key).deserialize { |value| string_value(value, "a borrowed string") }
        end

        # An optional string argument (a Rust Option<&str>, or with
        # <tt>expected: "a string"</tt> an Option<String>): absent or null
        # is +nil+.
        def self.optional_string_arg(invoke, key, expected: "a borrowed string") # :nodoc:
          argument(invoke, key).deserialize_option { |value| string_value(value, expected) }
        end

        # +value+ if it is a String, or serde's error naming +expected+:
        # serde's &str visitor expects "a borrowed string", its String
        # visitor "a string".
        def self.string_value(value, expected) # :nodoc:
          value.is_a?(String) ? value : raise(Tokra::Ipc::CommandItem::Mismatch.invalid_type(value, expected))
        end
        private_class_method :argument, :string_arg, :optional_string_arg, :string_value
      end
    end
  end
end

# Tauri's own global API script for the plugin, which defines
# window.__TAURI__.clipboardManager in a page with withGlobalTauri
# (build.rs:16; api-iife.js at plugins-workspace d4613ff0, unchanged).
Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("clipboard/api-iife.js", __dir__))

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Clipboard::ClipboardManagerExt)

# SPDX-SnippetEnd
