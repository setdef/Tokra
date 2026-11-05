# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: BundleResources adapted from tauri-utils src/config.rs:1229-1250
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The files the bundler copies beside the app.
      #
      # <tt>bundle.resources</tt> lists paths and glob patterns, which keep
      # their directories, or maps each source to where it goes. Tokra has
      # no bundler yet (TODO 002): an app run from source reads its files
      # where they are, so Tokra reads the setting and copies nothing.
      #
      # Mirrors Tauri's untagged <tt>BundleResources</tt>
      # (config.rs:1229-1250).
      #
      # === Examples
      #
      #   # "resources": ["data/*.json"]
      #   bundle.resources.paths  #=> ["data/*.json"]
      #
      #   # "resources": { "data/": "assets/" }
      #   bundle.resources.paths  #=> {"data/" => "assets/"}
      module BundleResources
        # The paths to copy, each kept under its own directories.
        class List < Data.define(:paths)
        end

        # Each source path, and where it goes.
        class Map < Data.define(:paths)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "BundleResources", [
            -> (raw) { List.new(paths: Utils::Config.sequence(raw) { |path| Ipc::Serde.string(path) }) },
            -> (raw) { Map.new(paths: Utils::Config.map(raw) { |path| Ipc::Serde.string(path) }) },
          ])
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
