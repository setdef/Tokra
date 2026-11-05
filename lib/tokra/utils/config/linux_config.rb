# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AppImageConfig, DebConfig, LinuxConfig, RpmCompression, and
#   RpmConfig adapted from tauri-utils src/config.rs:315-507 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # How the bundler builds the AppImage.
      #
      # Mirrors Tauri's <tt>AppImageConfig</tt> (config.rs:315-329).
      class AppImageConfig < Data.define(:bundle_media_framework, :files)
        FIELDS = [
          Field.defaulted(:bundle_media_framework, "bundleMediaFramework", -> (raw) { Ipc::Serde.boolean(raw) }, false,
            aliases: %w[bundle-media-framework]),
          Field.defaulted(:files, "files", -> (raw) { Utils::Config.path_map(raw) }, {}),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "AppImageConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # How the bundler builds the Debian package.
      #
      # Mirrors Tauri's <tt>DebConfig</tt> (config.rs:331-381).
      class DebConfig < Data.define(
        :depends, :recommends, :provides, :conflicts, :replaces, :files, :section, :priority, :changelog,
        :desktop_template, :pre_install_script, :post_install_script, :pre_remove_script, :post_remove_script
      )
        PATH = -> (raw) { Utils::Config.path(raw) } # :nodoc:
        STRINGS = -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } } # :nodoc:
        private_constant :PATH, :STRINGS

        FIELDS = [
          Field.option(:depends, "depends", STRINGS),
          Field.option(:recommends, "recommends", STRINGS),
          Field.option(:provides, "provides", STRINGS),
          Field.option(:conflicts, "conflicts", STRINGS),
          Field.option(:replaces, "replaces", STRINGS),
          Field.defaulted(:files, "files", -> (raw) { Utils::Config.path_map(raw) }, {}),
          Field.option(:section, "section", -> (raw) { Ipc::Serde.string(raw) }),
          Field.option(:priority, "priority", -> (raw) { Ipc::Serde.string(raw) }),
          Field.option(:changelog, "changelog", PATH),
          Field.option(:desktop_template, "desktopTemplate", PATH, aliases: %w[desktop-template]),
          Field.option(:pre_install_script, "preInstallScript", PATH, aliases: %w[pre-install-script]),
          Field.option(:post_install_script, "postInstallScript", PATH, aliases: %w[post-install-script]),
          Field.option(:pre_remove_script, "preRemoveScript", PATH, aliases: %w[pre-remove-script]),
          Field.option(:post_remove_script, "postRemoveScript", PATH, aliases: %w[post-remove-script]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "DebConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # How the RPM package is compressed, and how hard.
      #
      # Mirrors Tauri's internally tagged <tt>RpmCompression</tt>
      # (config.rs:402-430).
      #
      # === Example
      #
      #   # "compression": { "type": "zstd", "level": 19 }
      #   rpm.compression.level  #=> 19
      module RpmCompression
        # Gzip, at +level+.
        class Gzip < Data.define(:level)
        end

        # Zstandard, at +level+, which may be negative.
        class Zstd < Data.define(:level)
        end

        # XZ, at +level+.
        class Xz < Data.define(:level)
        end

        # Bzip2, at +level+.
        class Bzip2 < Data.define(:level)
        end

        # No compression.
        class None < Data.define
        end

        U32 = [Field.required(:level, "level", -> (raw) { Ipc::CommandItem.integer(raw, "u32") })].freeze # :nodoc:
        I32 = [Field.required(:level, "level", -> (raw) { Ipc::CommandItem.integer(raw, "i32") })].freeze # :nodoc:
        private_constant :U32, :I32

        # Reads +value+, a JSON value, as serde reads the enum: tagged by
        # its <tt>type</tt> key, each variant renamed camelCase.
        def self.deserialize(value) # :nodoc:
          variant, rest = Ipc::Serde.internally_tagged(value, "type", "RpmCompression", %w[gzip zstd xz bzip2 none])
          name = variant.capitalize
          if name == "None"
            Utils::Config.read_unit_variant(rest)
            return None.new
          end

          fields = (name == "Zstd") ? I32 : U32
          const_get(name, false).new(**Utils::Config.read_variant(rest, "RpmCompression::#{name}", fields))
        end
      end

      # How the bundler builds the RPM package.
      #
      # Mirrors Tauri's <tt>RpmConfig</tt> (config.rs:432-507).
      class RpmConfig < Data.define(
        :depends, :recommends, :provides, :conflicts, :obsoletes, :release, :epoch, :files, :desktop_template,
        :pre_install_script, :post_install_script, :pre_remove_script, :post_remove_script, :compression
      )
        PATH = -> (raw) { Utils::Config.path(raw) } # :nodoc:
        STRINGS = -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } } # :nodoc:
        private_constant :PATH, :STRINGS

        FIELDS = [
          Field.option(:depends, "depends", STRINGS),
          Field.option(:recommends, "recommends", STRINGS),
          Field.option(:provides, "provides", STRINGS),
          Field.option(:conflicts, "conflicts", STRINGS),
          Field.option(:obsoletes, "obsoletes", STRINGS),
          Field.defaulted(:release, "release", -> (raw) { Ipc::Serde.string(raw) }, "1"),
          Field.defaulted(:epoch, "epoch", -> (raw) { Ipc::CommandItem.integer(raw, "u32") }, 0),
          Field.defaulted(:files, "files", -> (raw) { Utils::Config.path_map(raw) }, {}),
          Field.option(:desktop_template, "desktopTemplate", PATH, aliases: %w[desktop-template]),
          Field.option(:pre_install_script, "preInstallScript", PATH, aliases: %w[pre-install-script]),
          Field.option(:post_install_script, "postInstallScript", PATH, aliases: %w[post-install-script]),
          Field.option(:pre_remove_script, "preRemoveScript", PATH, aliases: %w[pre-remove-script]),
          Field.option(:post_remove_script, "postRemoveScript", PATH, aliases: %w[post-remove-script]),
          Field.option(:compression, "compression", -> (raw) { RpmCompression.deserialize(raw) }),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "RpmConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # How the bundler packages the app for Linux.
      #
      # Tokra has no bundler yet (TODO 002), so it reads these settings
      # and builds nothing.
      #
      # Mirrors Tauri's <tt>LinuxConfig</tt> (config.rs:383-400).
      #
      # === Example
      #
      #   bundle.linux.rpm.release  #=> "1"
      class LinuxConfig < Data.define(:appimage, :deb, :rpm)
        FIELDS = [
          Field.defaulted(:appimage, "appimage", -> (raw) { AppImageConfig.deserialize(raw) }, AppImageConfig.new),
          Field.defaulted(:deb, "deb", -> (raw) { DebConfig.deserialize(raw) }, DebConfig.new),
          Field.defaulted(:rpm, "rpm", -> (raw) { RpmConfig.deserialize(raw) }, RpmConfig.new),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "LinuxConfig", FIELDS))
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
