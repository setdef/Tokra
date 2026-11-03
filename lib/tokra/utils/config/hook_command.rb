# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: BeforeDevCommand and HookCommand adapted from tauri-utils
#   src/config.rs:2964-2995 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The command to run before the app starts in development, such as
      # your frontend's dev server.
      #
      # Tauri's CLI runs it before <tt>tauri dev</tt>, and waits for it to
      # finish when <tt>wait</tt> is on. Tokra has no CLI yet, so it reads
      # the command and runs nothing (plan 054's inventory).
      #
      # Mirrors Tauri's untagged <tt>BeforeDevCommand</tt>
      # (config.rs:2964-2981).
      #
      # === Examples
      #
      #   # "beforeDevCommand": "npm run dev"
      #   build.before_dev_command.script  #=> "npm run dev"
      #
      #   # "beforeDevCommand": { "script": "npm run dev", "cwd": "web", "wait": true }
      #   build.before_dev_command.wait  #=> true
      module BeforeDevCommand
        # The command alone.
        class Script < Data.define(:script)
        end

        # The command, the directory it runs in (+nil+: the project's),
        # and whether to wait for it to finish.
        class ScriptWithOptions < Data.define(:script, :cwd, :wait)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "BeforeDevCommand", [
            -> (raw) { Script.new(script: Ipc::Serde.string(raw)) },
            lambda do |raw|
              defaults = { "wait" => false } #: Hash[String, String | bool]
              fields = Ipc::Serde.untagged_struct_variant(raw, "BeforeDevCommand::ScriptWithOptions", %w[script cwd wait],
                optional: %w[cwd], defaults:) do |field, item|
                (field == "wait") ? Ipc::Serde.boolean(item) : Ipc::Serde.string(item)
              end
              script = fields["script"] #: String
              cwd = fields["cwd"] #: String?
              wait = fields["wait"] #: bool
              ScriptWithOptions.new(script:, cwd:, wait:)
            end,
          ])
        end
      end

      # A command to run before the app is built or bundled.
      #
      # Tauri's CLI runs <tt>beforeBuildCommand</tt> and
      # <tt>beforeBundleCommand</tt> on <tt>tauri build</tt>. Tokra has no
      # CLI yet, so it reads them and runs nothing (plan 054's inventory).
      #
      # Mirrors Tauri's untagged <tt>HookCommand</tt> (config.rs:2983-2995).
      #
      # === Example
      #
      #   # "beforeBuildCommand": { "script": "npm run build", "cwd": "web" }
      #   build.before_build_command.cwd  #=> "web"
      module HookCommand
        # The command alone.
        class Script < Data.define(:script)
        end

        # The command and the directory it runs in (+nil+: the project's).
        class ScriptWithOptions < Data.define(:script, :cwd)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "HookCommand", [
            -> (raw) { Script.new(script: Ipc::Serde.string(raw)) },
            lambda do |raw|
              fields = Ipc::Serde.untagged_struct_variant(raw, "HookCommand::ScriptWithOptions", %w[script cwd],
                optional: %w[cwd]) { |_field, item| Ipc::Serde.string(item) }
              script = fields["script"] #: String
              cwd = fields["cwd"] #: String?
              ScriptWithOptions.new(script:, cwd:)
            end,
          ])
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
