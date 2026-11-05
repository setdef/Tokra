# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AndroidConfig adapted from tauri-utils src/config.rs:2893-2936
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # How Tauri's CLI builds the app for Android.
      #
      # Tokra runs on desktops only, so it reads these settings, as Tauri's
      # schema allows them in any config, and acts on none. The Play
      # Store's limit on +version_code+, 2,100,000,000, is a check of
      # Tauri's JSON schema, not of its parse, so a larger one reads here
      # as it does in Tauri.
      #
      # Mirrors Tauri's <tt>AndroidConfig</tt> (config.rs:2893-2936).
      #
      # === Example
      #
      #   bundle.android.min_sdk_version  #=> 24
      class AndroidConfig < Data.define(:min_sdk_version, :version_code, :auto_increment_version_code)
        U32 = -> (raw) { Ipc::CommandItem.integer(raw, "u32") } # :nodoc:
        private_constant :U32

        FIELDS = [
          # default_min_sdk_version (config.rs:2934-2936)
          Field.defaulted(:min_sdk_version, "minSdkVersion", U32, 24, aliases: %w[min-sdk-version]),
          Field.option(:version_code, "versionCode", U32, aliases: %w[version-code]),
          Field.defaulted(:auto_increment_version_code, "autoIncrementVersionCode", -> (raw) { Ipc::Serde.boolean(raw) }, false,
            aliases: %w[auto-increment-version-code]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "AndroidConfig", FIELDS))
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
