# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: RunnerConfig adapted from tauri-utils src/config.rs:2997-3068
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The program Tauri's CLI builds the app with, in place of Cargo.
      #
      # Tauri's CLI runs <tt>cargo</tt> unless the config names another
      # runner, such as <tt>cross</tt>, with its own directory and
      # arguments. Tokra has no CLI yet, so it reads the runner and runs
      # nothing (plan 054's inventory).
      #
      # The variants keep Tauri's names, String and Object, so inside this
      # module write <tt>::String</tt> and <tt>::Object</tt> for Ruby's.
      #
      # Mirrors Tauri's untagged <tt>RunnerConfig</tt> (config.rs:2997-3016).
      #
      # === Examples
      #
      #   # "runner": "cross"
      #   build.runner.cmd  #=> "cross"
      #
      #   # "runner": { "cmd": "cross", "args": ["--release"] }
      #   build.runner.args  #=> ["--release"]
      module RunnerConfig
        # The runner's command alone.
        class String < Data.define(:cmd)
        end

        # The runner's command, the directory it runs in, and its
        # arguments, either +nil+ when left out.
        class Object < Data.define(:cmd, :cwd, :args)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "RunnerConfig", [
            -> (raw) { String.new(cmd: Ipc::Serde.string(raw)) },
            lambda do |raw|
              fields = Ipc::Serde.untagged_struct_variant(raw, "RunnerConfig::Object", %w[cmd cwd args],
                optional: %w[cwd args]) do |field, item|
                (field == "args") ? Utils::Config.sequence(item) { |arg| Ipc::Serde.string(arg) } : Ipc::Serde.string(item)
              end
              cmd = fields["cmd"] #: ::String
              cwd = fields["cwd"] #: ::String?
              args = fields["args"] #: Array[::String]?
              Object.new(cmd:, cwd:, args:)
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
