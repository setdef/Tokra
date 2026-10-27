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

# The system's dialogs, through rfd (ADR 011). A failure to load it is a
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
    # Namespace for the dialog plugin.
    #
    # Use Tokra::Plugins::Dialog::Plugin as the plugin class.
    module Dialog
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
      # Tauri also defines <tt>window.__TAURI__.dialog</tt> when the app
      # sets +withGlobalTauri+. Tokra has no plugin global scripts yet, so
      # import the package through your bundler.
      #
      # == Ruby API
      #
      # Register the plugin on the app handle, for example in the setup
      # hook. It manages a Dialog, which every manager reaches as +dialog+:
      #
      #   Tokra::Builder.new
      #     .setup { |app| app.handle.plugin(Tokra::Plugins::Dialog::Plugin.new(app.handle)) }
      #     .run
      #
      #   handle.dialog.message("Saved").show { |_ok| }
      #   handle.dialog.file.pick_file { |path| p path }
      #
      # == Deviations
      #
      # * A dialog's parent is the calling window on Windows and X11 only.
      #   ferro-rfd binds no AppKit or Wayland handle, since rfd follows
      #   those as pointers (ADR 013). On macOS, file dialogs still slide
      #   out of the app's main window, but message dialogs are system
      #   alerts of their own.
      # * Picked paths join no fs or asset protocol scope; Tokra has
      #   neither yet.
      # * On Linux the dialogs come from the XDG desktop portal, with
      #   zenity for message dialogs, not GTK. On Windows, custom button
      #   labels show the standard ones; the commands still answer with
      #   your labels.
      # * A message dialog's default title is the app's product name, or
      #   empty.
      #
      # Mirrors Tauri's dialog plugin (lib.rs:184-212).
      class Plugin < Tokra::Plugin
        # Tauri's init script, unchanged: <tt>window.alert</tt> and
        # <tt>window.confirm</tt> call the message and confirm commands
        # (src/init-iife.js, built from guest-js/init.ts).
        INIT_SCRIPT = File.read(File.expand_path("dialog/init-iife.js", __dir__)).freeze

        # The commands the plugin answers (build.rs:5).
        COMMANDS = %w[open save message ask confirm].freeze

        # Returns the unique plugin identifier, "dialog" (lib.rs:187), the
        # name in <tt>plugin:dialog|open</tt>.
        def name
          "dialog"
        end

        # Registers the plugin with +app+, the app handle, and manages a
        # Dialog for it, the body of Tauri's setup closure (lib.rs:203-210).
        # A second plugin instance finds a Dialog already managed and
        # shares it.
        #
        #   handle.plugin(Tokra::Plugins::Dialog::Plugin.new(handle))
        def initialize(app, config = {})
          super
          app.manage(Dialog.new(app))
        end

        # Tauri's init script, which every page runs after Tauri's own
        # (lib.rs:189-193). Tauri leaves it out on Android only.
        def initialization_script
          INIT_SCRIPT
        end

        # Handles the open, save, message, ask, and confirm commands.
        #
        # Each checks its arguments now, rejecting a bad one with Tauri's
        # message, and then waits for the user on a thread of its own, so
        # the event loop keeps running. Returns +true+ for one of the
        # plugin's commands and +false+ for any other. Only an argument
        # that does not read rejects here; anything else is a bug, and
        # reaches the router.
        def extend_api(invoke)
          command = invoke.command
          return false unless COMMANDS.include?(command)

          dialog = app.dialog
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
      end
    end
  end
end

# Extend Manager when plugin file is loaded (matches Tauri pattern)
Tokra::Manager.include(Tokra::Plugins::Dialog::DialogExt)

# SPDX-SnippetEnd
