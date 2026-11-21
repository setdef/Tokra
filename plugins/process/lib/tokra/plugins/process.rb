# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: init adapted from tauri-plugin-process src/lib.rs, with its
#                      crate doc and README's usage

require "tokra"

require_relative "process/version"
require_relative "process/commands"

module Tokra
  # Namespace for Tokra plugins.
  module Plugins
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
    # With <tt>app.withGlobalTauri</tt> in your config, a page with no
    # bundler finds the same functions on <tt>window.__TAURI__.process</tt>:
    # the plugin ships Tauri's own <tt>api-iife.js</tt>, which every page
    # runs after Tauri's bundle. Require <tt>tokra-process</tt> before
    # Tokra.generate_context reads it.
    #
    # Tauri gates both commands behind its permissions,
    # <tt>process:allow-exit</tt> and <tt>process:allow-restart</tt>,
    # which its default set grants. Tokra has no capabilities yet: every
    # page of the app's own origin can call both, and other origins
    # neither.
    #
    # == Ruby API
    #
    # Register the plugin on the builder with ::init:
    #
    #   require "tokra-process"
    #
    #   Tokra::Builder.default
    #     .plugin(Tokra::Plugins::Process.init)
    #     .run(Tokra.generate_context)
    #
    # The plugin has no setup, so it never reads a
    # <tt>plugins.process</tt> in your config, as Tauri's does not.
    #
    # From Ruby, call the handle yourself: <tt>handle.exit(0)</tt> or
    # <tt>handle.request_restart</tt>.
    #
    # Inside <tt>module Tokra</tt>, a bare +Process+ names Tokra::Process,
    # Tauri's +process+ module; this one is Tokra::Plugins::Process.
    #
    # Mirrors Tauri's process plugin (lib.rs:19-23), which works on
    # Linux, Windows, and macOS, and not on Android or iOS.
    module Process
      # The commands the plugin answers (lib.rs:21).
      COMMANDS = %w[exit restart].freeze

      # Initializes the plugin: a Tokra::Plugin::TauriPlugin named
      # +process+, the name in <tt>plugin:process|exit</tt>, for
      # Tokra::Builder#plugin.
      #
      # Its invoke handler reads +exit+'s +code+ as Tauri's command macro
      # reads an +i32+, calls the command for the invoking webview's app,
      # and resolves the invoke with +nil+. It answers +true+ for one of
      # COMMANDS and +false+ for any other, so Tokra rejects the rest with
      # <tt>Command NAME not found</tt>, as Tauri does. A +code+ that does
      # not read rejects the invoke with Tauri's message, and the command
      # does not run; anything else is a bug, and reaches the router.
      #
      # Mirrors Tauri's <tt>init</tt> (lib.rs:19-23).
      #
      # === Example
      #
      #   Tokra::Builder.default.plugin(Tokra::Plugins::Process.init)
      def self.init
        Tokra::Plugin::Builder.new("process")
          .invoke_handler { |invoke| handle_invoke(invoke) }
          .build
      end

      # Runs one of COMMANDS for the invoking webview's app; answers
      # whether it was one of them.
      def self.handle_invoke(invoke) # :nodoc:
        app = invoke.webview.app_handle
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
      def self.exit_code(invoke) # :nodoc:
        Tokra::Ipc::CommandItem.new(name: "exit", key: "code", payload: invoke.body).deserialize do |value|
          Tokra::Ipc::CommandItem.integer(value, "i32")
        end
      end
      private_class_method :handle_invoke, :exit_code
    end
  end
end

# Tauri's own global API script for the plugin, which defines
# window.__TAURI__.process in a page with withGlobalTauri (build.rs:9;
# api-iife.js at plugins-workspace d4613ff0, unchanged).
Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("process/api-iife.js", __dir__))

# SPDX-SnippetEnd
