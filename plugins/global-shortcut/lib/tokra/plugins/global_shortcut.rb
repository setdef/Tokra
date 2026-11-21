# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Re-exports and COMMANDS adapted from tauri-plugin-global-shortcut
#                      src/lib.rs:1-36, 388-397

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
    # Global keyboard shortcuts for Tokra applications: Windows, Linux,
    # and macOS.
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
    # With <tt>app.withGlobalTauri</tt> in your config, a page with no
    # bundler finds the same functions on
    # <tt>window.__TAURI__.globalShortcut</tt>: the plugin ships Tauri's
    # own <tt>api-iife.js</tt>, which every page runs after Tauri's bundle.
    # Require <tt>tokra-global-shortcut</tt> before Tokra.generate_context
    # reads it.
    #
    # == Ruby API
    #
    # Make the plugin with Builder, Tauri's, and register it once, on the
    # builder. It manages a GlobalShortcut, which every manager reaches as
    # +global_shortcut+:
    #
    #   require "tokra-global-shortcut"
    #
    #   Tokra::Builder.default
    #     .plugin(Tokra::Plugins::GlobalShortcut::Builder.new.build)
    #     .run(Tokra.generate_context)
    #
    # The plugin takes no config: a non-null
    # <tt>plugins.global-shortcut</tt> in your config fails the app with
    # Tokra::Error::PluginInitialization, as Tauri's does.
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
    # * A handler runs after the plugin's lock is released, so it may
    #   register and unregister shortcuts, where Tauri deadlocks; an event
    #   read just before its shortcut is unregistered still reaches it.
    #   One that raises is reported with +warn+, where Tauri aborts.
    # * Shortcuts follow global-hotkey 0.9.0, which Ferro binds, not the
    #   0.7.0 Tauri locks: <tt>meta+</tt> where Tauri wrote
    #   <tt>super+</tt>, ids to match, and more keys.
    #
    # Mirrors Tauri's global-shortcut plugin (lib.rs:388-435).
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

      # The commands the plugin answers (lib.rs:392-397, build.rs:5).
      COMMANDS = %w[register unregister unregister_all is_registered].freeze
    end
  end
end

# Tauri's own global API script for the plugin, which defines
# window.__TAURI__.globalShortcut in a page with withGlobalTauri (build.rs:9;
# api-iife.js at plugins-workspace d4613ff0, unchanged).
Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("global_shortcut/api-iife.js", __dir__))

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::GlobalShortcut::GlobalShortcutExt)

# SPDX-SnippetEnd
