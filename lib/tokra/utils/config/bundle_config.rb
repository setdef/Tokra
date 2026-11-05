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
      # Tokra has no bundler yet (TODO 002), so it reads the whole bundle
      # and checks it as Tauri does, every key, alias, default, and refusal,
      # but acts only on <tt>copyright</tt> and <tt>publisher</tt>, in the
      # about box, and on <tt>icon</tt>, for the window and app icons.
      #
      # Mirrors Tauri's <tt>BundleConfig</tt> (config.rs:1281-1413).
      #
      # === Example
      #
      #   bundle = Tokra.generate_context.config.bundle
      #   bundle.copyright  #=> "Copyright 2026 Example Inc."
      #   bundle.icon       #=> ["icons/icon.png", "icons/icon.icns"]
      #   bundle.targets    #=> #<data Tokra::Utils::Config::BundleTarget::All>
      class BundleConfig < Data.define(
        :active, :targets, :create_updater_artifacts, :publisher, :homepage, :icon, :resources, :copyright, :license,
        :license_file, :category, :file_associations, :short_description, :long_description, :use_local_tools_dir,
        :external_bin, :windows, :linux, :macos, :ios, :android
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        STRINGS = -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } } # :nodoc:
        private_constant :STRING, :STRINGS

        FIELDS = [
          Field.defaulted(:active, "active", -> (raw) { Ipc::Serde.boolean(raw) }, false),
          Field.defaulted(:targets, "targets", -> (raw) { BundleTarget.deserialize(raw) }, BundleTarget::All.new),
          Field.defaulted(:create_updater_artifacts, "createUpdaterArtifacts", -> (raw) { Updater.deserialize(raw) },
            Updater::Bool.new(enabled: false)),
          Field.option(:publisher, "publisher", STRING),
          Field.option(:homepage, "homepage", STRING),
          Field.defaulted(:icon, "icon", STRINGS, []),
          Field.option(:resources, "resources", -> (raw) { BundleResources.deserialize(raw) }),
          Field.option(:copyright, "copyright", STRING),
          Field.option(:license, "license", STRING),
          Field.option(:license_file, "licenseFile", -> (raw) { Utils::Config.path(raw) }, aliases: %w[license-file]),
          Field.option(:category, "category", STRING),
          Field.option(:file_associations, "fileAssociations",
            -> (raw) { Utils::Config.sequence(raw) { |item| FileAssociation.deserialize(item) } }),
          Field.option(:short_description, "shortDescription", STRING, aliases: %w[short-description]),
          Field.option(:long_description, "longDescription", STRING, aliases: %w[long-description]),
          Field.defaulted(:use_local_tools_dir, "useLocalToolsDir", -> (raw) { Ipc::Serde.boolean(raw) }, false,
            aliases: %w[use-local-tools-dir]),
          Field.option(:external_bin, "externalBin", STRINGS, aliases: %w[external-bin]),
          Field.defaulted(:windows, "windows", -> (raw) { WindowsConfig.deserialize(raw) }, WindowsConfig.new),
          Field.defaulted(:linux, "linux", -> (raw) { LinuxConfig.deserialize(raw) }, LinuxConfig.new),
          Field.defaulted(:macos, "macOS", -> (raw) { MacConfig.deserialize(raw) }, MacConfig.new, aliases: %w[macos]),
          Field.defaulted(:ios, "iOS", -> (raw) { IosConfig.deserialize(raw) }, IosConfig.new, aliases: %w[ios]),
          Field.defaulted(:android, "android", -> (raw) { AndroidConfig.deserialize(raw) }, AndroidConfig.new),
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
