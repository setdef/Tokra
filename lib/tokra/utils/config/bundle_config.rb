# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: BundleConfig adapted from tauri-utils src/config.rs:1281-1413
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # How your app is packaged for each platform, and who made it.
      #
      # A bundler turns an app into an installer: it needs icons, a
      # publisher, a copyright line, and each platform's own settings. The
      # <tt>bundle</tt> key holds them. A running app reads a few of them
      # too: the about box shows the copyright and publisher, and the
      # window icon comes from <tt>icon</tt>.
      #
      # Tokra has no bundler yet (TODO 002), so it reads the bundle and
      # acts on <tt>copyright</tt> and <tt>publisher</tt> once the builder
      # takes a context, and on <tt>icon</tt> in plan 054's third phase.
      #
      # *Deviation until plan 054's fourth phase*: +targets+,
      # +create_updater_artifacts+, +resources+, +file_associations+,
      # +windows+, +linux+, +macos+, +ios+, and +android+ are their JSON, as
      # the config wrote them, so a key Tauri would refuse inside them
      # passes. Left out, each is the JSON that reads as Tauri's default:
      # <tt>"all"</tt>, +false+, +nil+, +nil+, and an empty Hash for each
      # platform.
      #
      # Mirrors Tauri's <tt>BundleConfig</tt> (config.rs:1281-1413).
      #
      # === Example
      #
      #   bundle = Tokra.generate_context.config.bundle
      #   bundle.copyright  #=> "Copyright 2026 Example Inc."
      #   bundle.icon       #=> ["icons/icon.png", "icons/icon.icns"]
      class BundleConfig < Data.define(
        :active, :targets, :create_updater_artifacts, :publisher, :homepage, :icon, :resources, :copyright, :license,
        :license_file, :category, :file_associations, :short_description, :long_description, :use_local_tools_dir,
        :external_bin, :windows, :linux, :macos, :ios, :android
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        STRINGS = -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } } # :nodoc:
        # The parts phase 4 types, kept as their JSON until then.
        RAW = -> (raw) { raw } # :nodoc:
        private_constant :STRING, :STRINGS, :RAW

        FIELDS = [
          Field.defaulted(:active, "active", -> (raw) { Ipc::Serde.boolean(raw) }, false),
          Field.defaulted(:targets, "targets", RAW, "all"),
          Field.defaulted(:create_updater_artifacts, "createUpdaterArtifacts", RAW, false),
          Field.option(:publisher, "publisher", STRING),
          Field.option(:homepage, "homepage", STRING),
          Field.defaulted(:icon, "icon", STRINGS, []),
          Field.option(:resources, "resources", RAW),
          Field.option(:copyright, "copyright", STRING),
          Field.option(:license, "license", STRING),
          Field.option(:license_file, "licenseFile", -> (raw) { Utils::Config.path(raw) }, aliases: %w[license-file]),
          Field.option(:category, "category", STRING),
          Field.option(:file_associations, "fileAssociations", RAW),
          Field.option(:short_description, "shortDescription", STRING, aliases: %w[short-description]),
          Field.option(:long_description, "longDescription", STRING, aliases: %w[long-description]),
          Field.defaulted(:use_local_tools_dir, "useLocalToolsDir", -> (raw) { Ipc::Serde.boolean(raw) }, false,
            aliases: %w[use-local-tools-dir]),
          Field.option(:external_bin, "externalBin", STRINGS, aliases: %w[external-bin]),
          Field.defaulted(:windows, "windows", RAW, {}),
          Field.defaulted(:linux, "linux", RAW, {}),
          Field.defaulted(:macos, "macOS", RAW, {}, aliases: %w[macos]),
          Field.defaulted(:ios, "iOS", RAW, {}, aliases: %w[ios]),
          Field.defaulted(:android, "android", RAW, {}),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "BundleConfig", FIELDS))
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
