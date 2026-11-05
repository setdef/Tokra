# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Updater and V1Compatible adapted from tauri-utils
#   src/config.rs:1252-1279 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The one legacy updater format: zipped artifacts Tauri 1's updater
      # reads.
      #
      # It is the only value, so V1Compatible.new is private.
      #
      # Mirrors Tauri's <tt>V1Compatible</tt> (config.rs:1272-1279).
      class V1Compatible < Data.define(:name)
        extend ClosedEnum

        ##
        # Tauri 1's zipped updater artifacts.
        V1Compatible = new(name: "V1Compatible")

        # Reads +value+, a JSON value, as serde reads the enum: a unit
        # variant renamed camelCase.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.unit_variant(value, %w[v1Compatible])
          self::V1Compatible
        end

        close
      end

      # Whether the bundler makes updater artifacts and their signatures.
      #
      # <tt>bundle.createUpdaterArtifacts</tt> is +true+ or +false+, or
      # <tt>"v1Compatible"</tt> for Tauri 1's zipped format. Tokra has no
      # bundler yet (TODO 002), so it reads the setting and makes nothing.
      #
      # The variants keep Tauri's names, String and Bool, so inside this
      # module write <tt>::String</tt> for Ruby's.
      #
      # Mirrors Tauri's untagged <tt>Updater</tt> (config.rs:1252-1270).
      #
      # === Examples
      #
      #   # no "createUpdaterArtifacts"
      #   bundle.create_updater_artifacts.enabled  #=> false
      #
      #   # "createUpdaterArtifacts": "v1Compatible"
      #   bundle.create_updater_artifacts.compatible  #=> Tokra::Utils::Config::V1Compatible::V1Compatible
      module Updater
        # The legacy format, V1Compatible::V1Compatible.
        class String < Data.define(:compatible)
        end

        # Whether to make updater artifacts at all.
        class Bool < Data.define(:enabled)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "Updater", [
            -> (raw) { String.new(compatible: V1Compatible.deserialize(raw)) },
            -> (raw) { Bool.new(enabled: Ipc::Serde.boolean(raw)) },
          ])
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
