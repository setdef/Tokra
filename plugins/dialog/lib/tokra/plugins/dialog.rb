# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Plugin adapted from tauri-plugin-dialog src/lib.rs:184-212

require "tokra"

# The system's dialogs, through rfd (ADR 020). A failure to load it is a
# real installation problem, so its LoadError propagates as-is.
require "ferro/rfd"

require_relative "dialog/version"
require_relative "dialog/models"
require_relative "dialog/desktop"
require_relative "dialog/message_dialog_builder"
require_relative "dialog/file_dialog_builder"
require_relative "dialog/dunce"
require_relative "dialog/commands"
require_relative "dialog/arguments"

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
    # Native file and message dialogs for Tokra desktop applications.
    #
    # A desktop app asks the user for files, tells them things, and asks
    # them to confirm. Users trust the system's own dialogs for that: the
    # open panel with their folders and favorites, the alert that looks
    # like every other alert.
    #
    # This plugin opens them through ferro-rfd, a one-to-one Ruby binding
    # of the rfd crate, and serves the commands of Tauri's dialog plugin,
    # so the frontend uses <tt>@tauri-apps/plugin-dialog</tt> unchanged.
    # Its init script also routes the page's <tt>window.alert</tt> and
    # <tt>window.confirm</tt> to the system's dialogs, as Tauri's does.
    #
    # Use it to pick files and folders, and to show messages and questions,
    # from Ruby or from the page.
    #
    # == JavaScript API (Tauri Compatibility)
    #
    #   import { open, save, message, ask, confirm } from '@tauri-apps/plugin-dialog';
    #
    #   const file = await open({ filters: [{ name: 'Image', extensions: ['png'] }] });
    #   const files = await open({ multiple: true });           // string[] | null
    #   const folder = await open({ directory: true });         // string | null
    #   const target = await save({ defaultPath: 'report.pdf' });
    #   await message('File not found', { title: 'Tokra', kind: 'error' });
    #   const yes = await ask('Delete it?', { kind: 'warning' });
    #   const ok = await confirm('Overwrite?', { okLabel: 'Overwrite' });
    #
    # Arguments are checked the way Tauri deserializes them: a missing or
    # mistyped argument rejects with Tauri's message, for example
    # <tt>invalid args `message` for command `ask`: command ask missing
    # required key message</tt>.
    #
    # With <tt>app.withGlobalTauri</tt> in your config, a page with no
    # bundler finds the same functions on <tt>window.__TAURI__.dialog</tt>:
    # the plugin ships Tauri's own <tt>api-iife.js</tt>, which every page
    # runs after Tauri's bundle. Require <tt>tokra-dialog</tt> before
    # Tokra.generate_context reads it.
    #
    # == Ruby API
    #
    # Register the plugin on the builder with ::init. It manages a Dialog,
    # which every manager reaches as +dialog+:
    #
    #   require "tokra-dialog"
    #
    #   Tokra::Builder.default
    #     .plugin(Tokra::Plugins::Dialog.init)
    #     .run(Tokra.generate_context)
    #
    #   handle.dialog.message("Saved").show { |_ok| }
    #   handle.dialog.file.pick_file { |path| p path }
    #
    # The plugin takes no config: a non-null <tt>plugins.dialog</tt> in
    # your config fails the app with Error::PluginInitialization, as
    # Tauri's does.
    #
    # == Deviations
    #
    # * A dialog's parent is the calling window on Windows and X11 only.
    #   ferro-rfd binds no AppKit or Wayland handle, since rfd follows
    #   those as pointers (ADR 020). On macOS, file dialogs still slide
    #   out of the app's main window, but message dialogs are system
    #   alerts of their own.
    # * Picked paths join no fs or asset protocol scope; Tokra has
    #   neither yet.
    # * On Linux the dialogs come from the XDG desktop portal, with
    #   zenity for message dialogs, not GTK. On Windows, custom button
    #   labels show the standard ones; the commands still answer with
    #   your labels.
    #
    # Mirrors Tauri's dialog plugin (lib.rs:184-212).
    module Dialog
      # Tauri's init script, unchanged: <tt>window.alert</tt> and
      # <tt>window.confirm</tt> call the message and confirm commands
      # (src/init-iife.js, built from guest-js/init.ts).
      INIT_SCRIPT = File.read(File.expand_path("dialog/init-iife.js", __dir__)).freeze

      # The commands the plugin answers (build.rs:5).
      COMMANDS = %w[open save message ask confirm].freeze

      # Initializes the plugin: a Tokra::Plugin::TauriPlugin named
      # +dialog+, the name in <tt>plugin:dialog|open</tt>, for
      # Tokra::Builder#plugin.
      #
      # Every page runs its init script after Tauri's own; Tauri leaves it
      # out on Android only. Its setup manages a Dialog for the app (a
      # second plugin finds one already managed and shares it). Each
      # command checks its arguments at once, rejecting a bad one with
      # Tauri's message, and then waits for the user on a thread of its
      # own, so the event loop keeps running; any other command is left
      # for the router, and anything else a command raises is a bug, and
      # reaches the router.
      #
      # Mirrors Tauri's <tt>init</tt> (lib.rs:184-212).
      #
      # === Example
      #
      #   Tokra::Builder.default.plugin(Tokra::Plugins::Dialog.init)
      def self.init
        Tokra::Plugin::Builder.new("dialog")
          .js_init_script(INIT_SCRIPT)
          .invoke_handler { |invoke| handle_invoke(invoke) }
          .setup { |app, _api| app.manage(Dialog.new(app)) }
          .build
      end

      # Runs one of COMMANDS against the Dialog the invoking webview's app
      # manages, as Tauri's commands take it as State; answers whether it
      # was one of them.
      def self.handle_invoke(invoke) # :nodoc:
        command = invoke.command
        return false unless COMMANDS.include?(command)

        dialog = invoke.webview.app_handle.dialog
        case command
        when "open" then Commands.open(invoke, dialog)
        when "save" then Commands.save(invoke, dialog)
        when "message" then Commands.message(invoke, dialog)
        when "ask" then Commands.ask(invoke, dialog)
        else Commands.confirm(invoke, dialog)
        end
      rescue Tokra::Error::InvalidArgs => e
        invoke.reject(e.message)
        true
      end
      private_class_method :handle_invoke
    end
  end
end

# Tauri's own global API script for the plugin, which defines
# window.__TAURI__.dialog in a page with withGlobalTauri (build.rs:9;
# api-iife.js at plugins-workspace d4613ff0, unchanged).
Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("dialog/api-iife.js", __dir__))

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Dialog::DialogExt)

# SPDX-SnippetEnd
