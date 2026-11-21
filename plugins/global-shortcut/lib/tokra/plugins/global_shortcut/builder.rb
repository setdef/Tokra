# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Builder adapted from tauri-plugin-global-shortcut src/lib.rs:336-435

module Tokra
  module Plugins
    module GlobalShortcut
      # Configures the plugin before it starts: the shortcuts it registers
      # at once, and one handler that hears all of them.
      #
      # An app with a fixed summon key, or a few keys of its own, wants them
      # registered as the app starts, and wants one place to react to every
      # press, rather than a handler per key.
      #
      # This builder collects those shortcuts and that handler. Its #build
      # makes the plugin, for Tokra::Builder#plugin, whose setup registers
      # the shortcuts when the app initializes it. The handler also hears every shortcut registered later,
      # through GlobalShortcut or the page, after that shortcut's own handler.
      #
      # Mirrors Tauri's global-shortcut <tt>Builder</tt> (lib.rs:336-435).
      #
      # === Examples
      #
      #   state = Tokra::Plugins::GlobalShortcut::ShortcutState
      #   shortcuts = Tokra::Plugins::GlobalShortcut::Builder.new
      #     .with_shortcuts(["CmdOrCtrl+Shift+D", "Alt+Space"])
      #     .with_handler { |handle, shortcut, event| handle.emit("shortcut", shortcut.to_s) if event.state == state::Pressed }
      #     .build
      #
      #   Tokra::Builder.default.plugin(shortcuts).run(Tokra.generate_context)
      #
      #   handle.plugin(Tokra::Plugins::GlobalShortcut::Builder.new.with_shortcut("Ctrl+D").build)
      class Builder
        # The Shortcuts setup registers. The plugin reads them.
        attr_reader :shortcuts # :nodoc:

        # The handler for every shortcut, or +nil+. The plugin reads it.
        attr_reader :handler # :nodoc:

        # A builder with no shortcuts and no handler (lib.rs:341-353).
        #
        # === Example
        #
        #   Tokra::Plugins::GlobalShortcut::Builder.new
        def initialize
          @shortcuts = [] #: Array[Shortcut]
          @handler = nil
        end

        # Add a shortcut to be registered: a Shortcut or a String. Raises
        # Error::GlobalHotkey when the string does not parse. Returns the
        # builder (lib.rs:355-363).
        #
        # === Example
        #
        #   builder.with_shortcut("CmdOrCtrl+Shift+D")
        def with_shortcut(shortcut)
          @shortcuts << Plugins::GlobalShortcut.try_into_shortcut(shortcut)
          self
        end

        # Add multiple shortcuts to be registered, as #with_shortcut does
        # for each. A string that does not parse raises before any is added.
        # Returns the builder (lib.rs:365-377).
        #
        # === Example
        #
        #   builder.with_shortcuts(["Ctrl+D", "Alt+Space"])
        def with_shortcuts(shortcuts)
          @shortcuts.concat(shortcuts.map { |shortcut| Plugins::GlobalShortcut.try_into_shortcut(shortcut) })
          self
        end

        # Specify a global shortcut handler that will be triggered for any
        # and all shortcuts: the block, which receives the app handle, the
        # Shortcut, and the ShortcutEvent. A later call replaces it. Returns
        # the builder (lib.rs:379-386).
        #
        # === Example
        #
        #   builder.with_handler { |_app, shortcut, event| puts "#{shortcut} #{event.state.debug}" }
        def with_handler(&handler)
          raise ArgumentError, "with_handler needs a block" unless handler

          @handler = handler
          self
        end

        # The plugin: a Tokra::Plugin::TauriPlugin named +global-shortcut+,
        # the name in <tt>plugin:global-shortcut|register</tt>, for
        # Tokra::Builder#plugin, taking no config.
        #
        # Its setup makes the hotkey manager on the main thread, registers
        # the builder's shortcuts, installs the event handler, and manages a
        # GlobalShortcut. When the manager or a shortcut fails, the app
        # reports Tokra::Error::PluginInitialization with global-hotkey's
        # message, after the setup unregisters the shortcuts it had
        # registered, as Rust's drop of the manager does. The shortcuts are
        # the builder's when #build is called; adding more later changes
        # nothing, as Tauri's +build+ consumes the builder (lib.rs:388-435).
        #
        # === Example
        #
        #   Tokra::Builder.default.plugin(builder.build)
        def build
          shortcuts = @shortcuts.dup.freeze
          handler = @handler
          Tokra::Plugin::Builder.new("global-shortcut")
            .invoke_handler { |invoke| handle_invoke(invoke) }
            .setup { |app, _api| setup(app, shortcuts, handler) }
            .build
        end

        # Tauri's setup (lib.rs:398-433) for +app+, with +shortcuts+ and the
        # global +handler+.
        private def setup(app, shortcuts, handler)
          context = app.runtime_context
          manager = context.getter { Ferro::GlobalHotkey::GlobalHotKeyManager.new }
          store = register_at_setup(context, manager, shortcuts)
          global_shortcut = GlobalShortcut.new(app, manager, store)
          ShortcutEvent.set_event_handler { |event| global_shortcut.handle_event(event, handler) }
          app.manage(global_shortcut)
          nil
        end

        # Runs one of COMMANDS against the GlobalShortcut the invoking
        # webview's app manages, as Tauri's commands take it as State;
        # answers whether it was one of them, so Tokra rejects the rest
        # with <tt>Command NAME not found</tt>, as Tauri does. An argument
        # that does not read, or the plugin's Error, rejects the invoke with
        # its message; anything else is a bug, and reaches the router.
        private def handle_invoke(invoke)
          command = invoke.command
          return false unless COMMANDS.include?(command)

          global_shortcut = invoke.webview.app_handle.global_shortcut
          case command
          when "register" then Commands.register(invoke, global_shortcut)
          when "unregister" then Commands.unregister(invoke, global_shortcut)
          when "unregister_all" then Commands.unregister_all(invoke, global_shortcut)
          else Commands.is_registered(invoke, global_shortcut)
          end
          true
        rescue Tokra::Error::InvalidArgs, Tokra::Ipc::InvokeError, Error => e
          invoke.reject(e.message)
          true
        end

        # Registers each of +shortcuts+ with +manager+ on the main thread
        # and returns the store, each with no handler of its own
        # (lib.rs:400-410).
        private def register_at_setup(context, manager, shortcuts)
          store = {} #: Hash[Integer, GlobalShortcut::RegisteredShortcut]
          shortcuts.each do |shortcut|
            context.getter { manager.register(shortcut) }
            store[shortcut.id] = GlobalShortcut::RegisteredShortcut.new(shortcut:, handler: nil)
          end
          store
        rescue Ferro::GlobalHotkey::Error
          release_at_setup(context, manager, store.to_h.values.map(&:shortcut))
          raise
        end

        # Unregisters +shortcuts+, which a failed setup had registered, and
        # ignores a refusal: Rust's manager unregisters them as it drops.
        private def release_at_setup(context, manager, shortcuts)
          context.getter { manager.unregister_all(shortcuts) } unless shortcuts.empty?
        rescue Ferro::GlobalHotkey::Error
          nil
        end
      end
    end
  end
end

# SPDX-SnippetEnd
