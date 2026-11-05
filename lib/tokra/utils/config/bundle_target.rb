# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: BundleType and BundleTarget adapted from tauri-utils
#   src/config.rs:128-311 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # A kind of installer a bundler can make.
      #
      # Tauri's bundler makes a <tt>.deb</tt>, an RPM, or an AppImage on
      # Linux, an MSI or an NSIS installer on Windows, and an app bundle or
      # a disk image on macOS. The config names them by their extension,
      # in any case. Tokra has no bundler yet (TODO 002), so it reads the
      # names and makes nothing.
      #
      # These seven are the only kinds, so BundleType.new is private.
      #
      # Mirrors Tauri's <tt>BundleType</tt> (config.rs:128-206).
      #
      # === Example
      #
      #   # "targets": "AppImage"
      #   bundle.targets.target       #=> Tokra::Utils::Config::BundleType::AppImage
      #   bundle.targets.target.to_s  #=> "appimage"
      class BundleType < Data.define(:name)
        extend ClosedEnum

        ##
        # The Debian package (<tt>.deb</tt>).
        Deb = new(name: "Deb")
        # The RPM package (<tt>.rpm</tt>).
        Rpm = new(name: "Rpm")
        # The AppImage (<tt>.appimage</tt>).
        AppImage = new(name: "AppImage")
        # The Microsoft Installer (<tt>.msi</tt>).
        Msi = new(name: "Msi")
        # The NSIS installer (<tt>.exe</tt>).
        Nsis = new(name: "Nsis")
        # The macOS application bundle (<tt>.app</tt>).
        App = new(name: "App")
        # The Apple Disk Image (<tt>.dmg</tt>).
        Dmg = new(name: "Dmg")

        # Every kind, in Tauri's order (<tt>BundleType::all</tt>,
        # config.rs:149-162).
        ALL = [Deb, Rpm, AppImage, Msi, Nsis, App, Dmg].freeze # :nodoc:

        # The kind's name as the config writes it, lowercase, as Tauri's
        # Display writes it (config.rs:164-180).
        def to_s
          name.downcase
        end

        # Reads +value+, a JSON value, as Tauri's own Deserialize reads it:
        # a string, matched without regard to case (config.rs:190-206).
        def self.deserialize(value) # :nodoc:
          string = Ipc::Serde.string(value)
          ALL.find { |type| type.to_s == string.downcase } ||
            raise(Ipc::CommandItem::Mismatch, "unknown bundle target '#{string}'")
        end

        close
      end

      # The installers to make: all of them, a list, or one.
      #
      # The config's <tt>bundle.targets</tt> takes <tt>"all"</tt>, one
      # BundleType's name, or a list of names, in any case. Tokra reads it
      # and makes nothing (TODO 002).
      #
      # Mirrors Tauri's <tt>BundleTarget</tt> (config.rs:208-311).
      #
      # === Examples
      #
      #   # "targets": "all", or no "targets"
      #   bundle.targets  #=> #<data Tokra::Utils::Config::BundleTarget::All>
      #
      #   # "targets": ["deb", "rpm"]
      #   bundle.targets.targets  #=> [Tokra::Utils::Config::BundleType::Deb, Tokra::Utils::Config::BundleType::Rpm]
      module BundleTarget
        # Every installer.
        class All < Data.define
        end

        # The installers listed, in order.
        class List < Data.define(:targets)
        end

        # The one installer named.
        class One < Data.define(:target)
        end

        # The message for a string that names neither <tt>all</tt> nor a
        # kind (config.rs:289-295).
        INVALID = "invalid bundle type %s, expected one of `all`, #{BundleType::ALL.map { |type| "`#{type}`" }.join(', ')}"
        private_constant :INVALID

        # Reads +value+, a JSON value, as Tauri's own Deserialize reads it:
        # through its untagged <tt>BundleTargetInner</tt>, a list, then one
        # kind, then any string, which must be <tt>all</tt> in any case
        # (config.rs:274-299).
        def self.deserialize(value) # :nodoc:
          inner = Ipc::Serde.untagged(value, "BundleTargetInner", [
            -> (raw) { List.new(targets: Utils::Config.sequence(raw) { |item| BundleType.deserialize(item) }) },
            -> (raw) { One.new(target: BundleType.deserialize(raw)) },
            -> (raw) { Ipc::Serde.string(raw) },
          ])
          return inner unless inner.is_a?(::String)
          raise Ipc::CommandItem::Mismatch, format(INVALID, inner) unless inner.downcase == "all"

          All.new
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
