# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: IosConfig adapted from tauri-utils src/config.rs:695-697,
#   2842-2891 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # How Tauri's CLI builds the app for iOS.
      #
      # Tokra runs on desktops only, so it reads these settings, as Tauri's
      # schema allows them in any config, and acts on none.
      #
      # Mirrors Tauri's <tt>IosConfig</tt> (config.rs:2842-2891).
      #
      # === Example
      #
      #   bundle.ios.minimum_system_version  #=> "14.0"
      class IosConfig < Data.define(
        :template, :frameworks, :development_team, :bundle_version, :minimum_system_version, :info_plist
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        PATH = -> (raw) { Utils::Config.path(raw) } # :nodoc:
        private_constant :STRING, :PATH

        FIELDS = [
          Field.option(:template, "template", PATH),
          Field.option(:frameworks, "frameworks", -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } }),
          Field.option(:development_team, "developmentTeam", STRING, aliases: %w[development-team]),
          Field.option(:bundle_version, "bundleVersion", STRING, aliases: %w[bundle-version]),
          # ios_minimum_system_version (config.rs:695-697)
          Field.defaulted(:minimum_system_version, "minimumSystemVersion", STRING, "14.0",
            aliases: %w[minimum-system-version]),
          Field.option(:info_plist, "infoPlist", PATH, aliases: %w[info-plist]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "IosConfig", FIELDS))
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
