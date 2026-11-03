# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: BuildConfig adapted from tauri-utils src/config.rs:3070-3131
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # How your app's frontend is built and found.
      #
      # While you work, your frontend usually runs on a dev server; once
      # built, it is a directory of files. The <tt>build</tt> key names
      # both, and the commands Tauri's CLI runs around a build.
      #
      # Tokra reads every key now. <tt>devUrl</tt> and a
      # <tt>frontendDist</tt> URL become the app's URL in plan 054a-5; the
      # commands, the runner, and the features wait for a Tokra CLI (plan
      # 054's inventory).
      #
      # Mirrors Tauri's <tt>BuildConfig</tt> (config.rs:3070-3131).
      #
      # === Example
      #
      #   build = Tokra.generate_context.config.build
      #   build.dev_url.as_str  #=> "http://localhost:1420/"
      #   build.frontend_dist  #=> #<data Tokra::Utils::Config::FrontendDist::Directory path=#<Pathname:../dist>>
      class BuildConfig < Data.define(
        :runner, :dev_url, :frontend_dist, :before_dev_command, :before_build_command, :before_bundle_command, :features,
        :remove_unused_commands, :additional_watch_folders
      )
        HOOK = -> (raw) { HookCommand.deserialize(raw) } # :nodoc:
        private_constant :HOOK

        FIELDS = [
          Field.option(:runner, "runner", -> (raw) { RunnerConfig.deserialize(raw) }),
          Field.option(:dev_url, "devUrl", -> (raw) { Utils::Config.url(raw) }, aliases: %w[dev-url]),
          Field.option(:frontend_dist, "frontendDist", -> (raw) { FrontendDist.deserialize(raw) },
            aliases: %w[frontend-dist]),
          Field.option(:before_dev_command, "beforeDevCommand", -> (raw) { BeforeDevCommand.deserialize(raw) },
            aliases: %w[before-dev-command]),
          Field.option(:before_build_command, "beforeBuildCommand", HOOK, aliases: %w[before-build-command]),
          Field.option(:before_bundle_command, "beforeBundleCommand", HOOK, aliases: %w[before-bundle-command]),
          Field.option(:features, "features", -> (raw) { Utils::Config.sequence(raw) { |feature| Ipc::Serde.string(feature) } }),
          Field.defaulted(:remove_unused_commands, "removeUnusedCommands", -> (raw) { Ipc::Serde.boolean(raw) }, false,
            aliases: %w[remove-unused-commands]),
          # The alias is Tauri's, "directories" where the key says "folders".
          Field.defaulted(:additional_watch_folders, "additionalWatchFolders",
            -> (raw) { Utils::Config.sequence(raw) { |path| Utils::Config.path(path) } }, [],
            aliases: %w[additional-watch-directories]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "BuildConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
