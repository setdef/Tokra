# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Position, Size, DmgConfig, de_macos_minimum_system_version, and
#   MacConfig adapted from tauri-utils src/config.rs:509-693 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # A point in whole pixels, as the disk image's window takes one.
      #
      # Mirrors Tauri's <tt>Position</tt> (config.rs:509-517).
      class Position < Data.define(:x, :y)
        FIELDS = [
          Field.required(:x, "x", -> (raw) { Ipc::CommandItem.integer(raw, "u32") }),
          Field.required(:y, "y", -> (raw) { Ipc::CommandItem.integer(raw, "u32") }),
        ].freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "Position", FIELDS)) # steep:ignore UnresolvedOverloading
        end
      end

      # A size in whole pixels, as the disk image's window takes one.
      #
      # Mirrors Tauri's <tt>Size</tt> (config.rs:531-539).
      class Size < Data.define(:width, :height)
        FIELDS = [
          Field.required(:width, "width", -> (raw) { Ipc::CommandItem.integer(raw, "u32") }),
          Field.required(:height, "height", -> (raw) { Ipc::CommandItem.integer(raw, "u32") }),
        ].freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "Size", FIELDS)) # steep:ignore UnresolvedOverloading
        end
      end

      # How the bundler lays out the disk image's window.
      #
      # Mirrors Tauri's <tt>DmgConfig</tt> (config.rs:541-593).
      class DmgConfig < Data.define(:background, :window_position, :window_size, :app_position, :application_folder_position)
        POSITION = -> (raw) { Position.deserialize(raw) } # :nodoc:
        private_constant :POSITION

        FIELDS = [
          Field.option(:background, "background", -> (raw) { Utils::Config.path(raw) }),
          Field.option(:window_position, "windowPosition", POSITION),
          Field.defaulted(:window_size, "windowSize", -> (raw) { Size.deserialize(raw) }, Size.new(width: 660, height: 400),
            aliases: %w[window-size]),
          Field.defaulted(:app_position, "appPosition", POSITION, Position.new(x: 180, y: 170), aliases: %w[app-position]),
          Field.defaulted(:application_folder_position, "applicationFolderPosition", POSITION, Position.new(x: 480, y: 170),
            aliases: %w[application-folder-position]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "DmgConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # How the bundler builds and signs the app for macOS.
      #
      # Tokra has no bundler yet (TODO 002), so it reads these settings
      # and builds nothing.
      #
      # +minimum_system_version+ defaults to <tt>"10.13"</tt>, and an empty
      # string reads as that default; +nil+, written <tt>null</tt>, means
      # no minimum at all (config.rs:595-604, 638-650).
      #
      # Mirrors Tauri's <tt>MacConfig</tt> (config.rs:606-693).
      #
      # === Example
      #
      #   bundle.macos.minimum_system_version  #=> "10.13"
      class MacConfig < Data.define(
        :frameworks, :files, :bundle_version, :bundle_name, :minimum_system_version, :exception_domain,
        :signing_identity, :hardened_runtime, :provider_short_name, :entitlements, :info_plist, :dmg
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        private_constant :STRING

        # The default minimum macOS version (config.rs:691-693).
        MINIMUM_SYSTEM_VERSION = "10.13" # :nodoc:

        FIELDS = [
          Field.option(:frameworks, "frameworks", -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } }),
          Field.defaulted(:files, "files", -> (raw) { Utils::Config.path_map(raw) }, {}),
          Field.option(:bundle_version, "bundleVersion", STRING, aliases: %w[bundle-version]),
          Field.option(:bundle_name, "bundleName", STRING, aliases: %w[bundle-name]),
          Field.defaulted(:minimum_system_version, "minimumSystemVersion",
            -> (raw) { de_macos_minimum_system_version(raw) }, MINIMUM_SYSTEM_VERSION, aliases: %w[minimum-system-version]),
          Field.option(:exception_domain, "exceptionDomain", STRING, aliases: %w[exception-domain]),
          Field.option(:signing_identity, "signingIdentity", STRING, aliases: %w[signing-identity]),
          Field.defaulted(:hardened_runtime, "hardenedRuntime", -> (raw) { Ipc::Serde.boolean(raw) }, true,
            aliases: %w[hardened-runtime]),
          Field.option(:provider_short_name, "providerShortName", STRING, aliases: %w[provider-short-name]),
          Field.option(:entitlements, "entitlements", STRING),
          Field.option(:info_plist, "infoPlist", -> (raw) { Utils::Config.path(raw) }, aliases: %w[info-plist]),
          Field.defaulted(:dmg, "dmg", -> (raw) { DmgConfig.deserialize(raw) }, DmgConfig.new),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "MacConfig", FIELDS))
        end

        # Reads the minimum macOS version as Tauri's
        # <tt>de_macos_minimum_system_version</tt> does: an
        # <tt>Option<String></tt>, with an empty string read as the default
        # (config.rs:595-604).
        def self.de_macos_minimum_system_version(value) # :nodoc:
          return nil if value.nil?

          version = Ipc::Serde.string(value)
          version.empty? ? MINIMUM_SYSTEM_VERSION : version
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
