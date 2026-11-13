# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Plugin adapted from tauri-plugin-process src/lib.rs, with its
#                      crate doc and README's usage

require "tokra"

require_relative "process/version"
require_relative "process/commands"

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
    # Namespace for the process plugin.
    #
    # Use Tokra::Plugins::Process::Plugin as the plugin class. Inside
    # <tt>module Tokra</tt>, a bare +Process+ names Tokra::Process, Tauri's
    # +process+ module; this one is Tokra::Plugins::Process.
    module Process
      # Access to the current process of your Tokra app.
      #
      # A desktop app often wants its page to end it, from a Quit button,
      # or to start it over, after an update or a change of settings that
      # only takes effect at launch. The page cannot end or restart the
      # Ruby process behind it.
      #
      # This plugin serves the commands of Tauri's process plugin, so the
      # frontend uses <tt>@tauri-apps/plugin-process</tt> unchanged: +exit+
      # asks the app to exit through AppHandle#exit, and +relaunch+ asks it
      # to restart through AppHandle#request_restart. To spawn child
      # processes, use Ruby's own <tt>::Process.spawn</tt>; Tauri points to
      # its shell plugin, which Tokra has not ported.
      #
      # == JavaScript API (Tauri Compatibility)
      #
      #   import { exit, relaunch } from '@tauri-apps/plugin-process';
      #
      #   await exit(0);      // exit the app with the given status code
      #   await relaunch();   // restart the app
      #
      # Both promises resolve with +undefined+ once the request is made,
      # usually before the app ends. +exit+ sends its code, 0 when given
      # none; one that is not a whole number in the range of a Rust +i32+
      # rejects with Tauri's message, for example <tt>invalid args `code`
      # for command `exit`: invalid type: floating point `1.5`, expected
      # i32</tt>, and the app keeps running.
      #
      # +exit+ asks rather than ends: your App#run callback and every
      # plugin hear RunEvent::ExitRequested with the code, and one that
      # calls <tt>api.prevent_exit</tt> keeps the app running. Otherwise
      # they hear RunEvent::Exit and the app ends with the code.
      #
      # +relaunch+ cannot be prevented. The app hears ExitRequested with
      # RESTART_EXIT_CODE and RunEvent::Exit, then Ruby runs your script
      # again, with the same arguments, and this process ends with status
      # 0 (Tokra::Process.restart). On macOS, a Ruby reached through a
      # symlink is refused, as Tauri refuses a binary reached through one
      # unless an app opts out with a Cargo feature; Tokra has no opt-out,
      # and the app then exits without starting again. An app run with
      # <tt>ruby -e</tt> has no script to run again, and likewise exits.
      #
      # Tauri also defines <tt>window.__TAURI__.process</tt> when the app
      # sets +withGlobalTauri+. Tokra has no plugin global scripts yet, so
      # import the package through your bundler.
      #
      # Tauri gates both commands behind its permissions,
      # <tt>process:allow-exit</tt> and <tt>process:allow-restart</tt>,
      # which its default set grants. Tokra has no capabilities yet: every
      # page of the app's own origin can call both, and other origins
      # neither.
      #
      # == Ruby API
      #
      # Register the plugin on the app handle:
      #
      #   app = Tokra::Builder.default.build(Tokra.generate_context)
      #   app.handle.plugin(Tokra::Plugins::Process::Plugin.new(app.handle))
      #   app.run
      #
      # From Ruby, call the handle yourself: <tt>handle.exit(0)</tt> or
      # <tt>handle.request_restart</tt>.
      #
      # Mirrors Tauri's process plugin (lib.rs:19-23), which works on
      # Linux, Windows, and macOS, and not on Android or iOS.
      class Plugin < Tokra::Plugin
        # The commands the plugin answers (lib.rs:21).
        COMMANDS = %w[exit restart].freeze

        # Returns the unique plugin identifier, "process" (lib.rs:20), the
        # name in <tt>plugin:process|exit</tt>.
        def name
          "process"
        end

        # Handles the exit and restart commands.
        #
        # Reads +exit+'s +code+ as Tauri's command macro reads an +i32+,
        # calls the command, and resolves the invoke with +nil+. Returns
        # +true+ for one of the plugin's commands and +false+ for any
        # other, so Tokra rejects the rest with <tt>Command NAME not
        # found</tt>, as Tauri does. A +code+ that does not read rejects
        # the invoke with Tauri's message, and the command does not run;
        # anything else is a bug, and reaches the router.
        def extend_api(invoke)
          case invoke.command
          when "exit" then invoke.resolve(Commands.exit(app, exit_code(invoke)))
          when "restart" then invoke.resolve(Commands.restart(app))
          else return false
          end
          true
        rescue Tokra::Error::InvalidArgs => e
          invoke.reject(e.message)
          true
        end

        # The +code+ argument of +exit+, read as the
        # <tt>#[tauri::command]</tt> macro reads <tt>code: i32</tt>
        # (commands.rs:8; Tauri's ipc/command.rs:60-102).
        private def exit_code(invoke)
          Tokra::Ipc::CommandItem.new(name: "exit", key: "code", payload: invoke.body).deserialize do |value|
            Tokra::Ipc::CommandItem.integer(value, "i32")
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
