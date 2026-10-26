# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Plugin and re-exports adapted from tauri-plugin-global-shortcut
#                      src/lib.rs:1-36, 388-435

require "tokra"

# Global hotkeys, through global-hotkey (ADR 011). A failure to load it is a
# real installation problem, so its LoadError propagates as-is.
require "ferro/global_hotkey"

require_relative "global_shortcut/version"
require_relative "global_shortcut/error"
require_relative "global_shortcut/global_shortcut"
require_relative "global_shortcut/commands"
require_relative "global_shortcut/builder"

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
    # Register global shortcuts.
    #
    # Supported platforms: Windows, Linux, and macOS.
    #
    # Use Tokra::Plugins::GlobalShortcut::Plugin as the plugin class, or
    # Builder to give it shortcuts and a handler of its own.
    module GlobalShortcut
      # A keyboard shortcut: modifiers and one key. global-hotkey's
      # +HotKey+, which Tauri re-exports as +Shortcut+ (lib.rs:22-25).
      Shortcut = Ferro::GlobalHotkey::Hotkey::HotKey

      # The physical keys, global-hotkey's re-export of keyboard-types'
      # +Code+ (lib.rs:23).
      Code = Ferro::GlobalHotkey::Hotkey::Code

      # The modifier keys, keyboard-types' +Modifiers+ (lib.rs:23).
      Modifiers = Ferro::GlobalHotkey::Hotkey::Modifiers

      # A press or release of a registered shortcut, with its id and
      # state: global-hotkey's +GlobalHotKeyEvent+ (lib.rs:24).
      ShortcutEvent = Ferro::GlobalHotkey::GlobalHotKeyEvent

      # Whether a shortcut went down (+Pressed+) or came up (+Released+):
      # global-hotkey's +HotKeyState+ (lib.rs:24).
      ShortcutState = Ferro::GlobalHotkey::HotKeyState

      # Global keyboard shortcuts for Tokra applications.
      #
      # A keyboard shortcut normally reaches only the window that has
      # focus. A launcher, a push-to-talk button, or a screenshot tool wants
      # its shortcut to work from anywhere, while another app is in front,
      # and each system grants that its own way.
      #
      # This plugin registers system-wide shortcuts through
      # ferro-global-hotkey, a one-to-one Ruby binding of global-hotkey,
      # Tauri's hotkey crate, and serves the commands of Tauri's
      # global-shortcut plugin, so the frontend uses
      # <tt>@tauri-apps/plugin-global-shortcut</tt> unchanged.
      #
      # == JavaScript API (Tauri Compatibility)
      #
      #   import { register, isRegistered, unregister, unregisterAll } from '@tauri-apps/plugin-global-shortcut';
      #
      #   await register('CommandOrControl+Shift+C', (event) => {
      #     if (event.state === 'Pressed') console.log(`${event.shortcut} triggered`);
      #   });
      #   await isRegistered('CommandOrControl+Shift+C');  // true
      #   await unregister('CommandOrControl+Shift+C');
      #   await unregisterAll();
      #
      # A shortcut that does not parse rejects with global-hotkey's message,
      # and a bad argument with Tauri's, for example <tt>invalid args
      # `shortcuts` for command `register`: invalid type: integer `1`,
      # expected a string</tt>. Each event's +shortcut+ is the shortcut's
      # own text, such as <tt>shift+control+F19</tt>.
      #
      # Tauri also defines <tt>window.__TAURI__.globalShortcut</tt> when the
      # app sets +withGlobalTauri+. Tokra has no plugin global scripts yet,
      # so import the package through your bundler.
      #
      # == Ruby API
      #
      # Register the plugin once, on the app handle, for example in the
      # setup hook. It manages a GlobalShortcut, which every manager
      # reaches as +global_shortcut+:
      #
      #   Tokra::Builder.default
      #     .setup(&Ractor.shareable_proc { |app| app.handle.plugin(Tokra::Plugins::GlobalShortcut::Plugin.new(app.handle)) })
      #     .run
      #
      #   handle.global_shortcut.on_shortcut("Alt+Space") { |app, shortcut, event| app.emit("summon", nil) }
      #
      # == Threads
      #
      # The system ties its hotkey manager to the main thread on macOS and
      # Windows, so the plugin makes it there and sends every call there.
      # Each press reaches your handler on a thread of its own, never the
      # main thread, so the window keeps running while it works.
      #
      # global-hotkey keeps one event handler for the whole process, set by
      # the first plugin, so only the first plugin in a process hears its
      # shortcuts, as in Tauri. On macOS only one hotkey manager can live at
      # a time, so a second plugin fails its setup. Register the plugin
      # once. No other library in the process may link global-hotkey.
      #
      # == Deviations
      #
      # * <tt>Builder#build</tt> takes the app handle.
      # * A handler runs after the plugin's lock is released, so it may
      #   register and unregister shortcuts, where Tauri deadlocks; an event
      #   read just before its shortcut is unregistered still reaches it.
      #   One that raises is reported with +warn+, where Tauri aborts.
      # * Shortcuts follow global-hotkey 0.9.0, which Ferro binds, not the
      #   0.7.0 Tauri locks: <tt>meta+</tt> where Tauri wrote
      #   <tt>super+</tt>, ids to match, and more keys.
      # * <tt>window.__TAURI__.globalShortcut</tt> is not defined.
      #
      # Mirrors Tauri's global-shortcut plugin (lib.rs:388-435).
      class Plugin < Tokra::Plugin
        # The commands the plugin answers (lib.rs:392-397, build.rs:5).
        COMMANDS = %w[register unregister unregister_all is_registered].freeze

        # Returns the unique plugin identifier, "global-shortcut"
        # (lib.rs:391), the name in <tt>plugin:global-shortcut|register</tt>.
        def name
          "global-shortcut"
        end

        # Registers the plugin with +app+, the app handle, running Tauri's
        # setup (lib.rs:398-433): it makes the hotkey manager on the main
        # thread, registers +builder+'s shortcuts, installs the event
        # handler, and manages a GlobalShortcut. Raises
        # Tokra::Error::PluginInitialization with global-hotkey's message
        # when the manager or a shortcut fails, after unregistering the
        # shortcuts it had registered, as Rust's drop of the manager does.
        #
        #   handle.plugin(Tokra::Plugins::GlobalShortcut::Plugin.new(handle))
        def initialize(app, builder = Builder.new)
          super(app)
          context = app.runtime_context
          manager = context.getter { Ferro::GlobalHotkey::GlobalHotKeyManager.new }
          store = register_at_setup(context, manager, builder.shortcuts)
          global_shortcut = GlobalShortcut.new(app, manager, store)
          handler = builder.handler
          ShortcutEvent.set_event_handler { |event| global_shortcut.handle_event(event, handler) }
          app.manage(global_shortcut)
        rescue Ferro::GlobalHotkey::Error => e
          raise Tokra::Error::PluginInitialization.new(name, e.message)
        end

        # Handles the register, unregister, unregister_all, and
        # is_registered commands.
        #
        # Returns +true+ for one of the plugin's commands and +false+ for
        # any other, so Tokra rejects the rest with <tt>Command NAME not
        # found</tt>, as Tauri does. An argument that does not read, or the
        # plugin's Error, rejects the invoke with its message; anything
        # else is a bug, and reaches the router.
        def extend_api(invoke)
          command = invoke.command
          return false unless COMMANDS.include?(command)

          global_shortcut = app.global_shortcut
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

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::GlobalShortcut::GlobalShortcutExt)

# SPDX-SnippetEnd
