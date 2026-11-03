# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: FsScope and AssetProtocolConfig adapted from tauri-utils
#   src/config.rs:2217-2286 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The files a protocol may serve.
      #
      # The asset protocol serves files from disk to your pages. Serving
      # any file would hand a page the whole disk, so a scope lists the
      # paths allowed, as glob patterns, and optionally those denied.
      #
      # Mirrors Tauri's untagged <tt>FsScope</tt> (config.rs:2217-2257).
      #
      # === Examples
      #
      #   # "scope": ["$APPDATA/**"]
      #   scope.paths  #=> [#<Pathname:$APPDATA/**>]
      #
      #   # "scope": { "allow": ["$APPDATA/**"], "deny": ["$APPDATA/secret"] }
      #   scope.deny  #=> [#<Pathname:$APPDATA/secret>]
      module FsScope
        # The allowed paths alone.
        class AllowedPaths < Data.define(:paths)
        end

        # The allowed and denied paths, and whether a glob's leading dot
        # has to be written out to match a dotfile (+nil+: the platform's
        # default).
        class Scope < Data.define(:allow, :deny, :require_literal_leading_dot)
        end

        SCOPE_FIELDS = %w[allow deny requireLiteralLeadingDot].freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "FsScope", [-> (raw) { AllowedPaths.new(paths: paths(raw)) }, -> (raw) { scope(raw) }])
        end

        def self.scope(value) # :nodoc:
          defaults = { "allow" => [], "deny" => [] } #: Hash[String, Array[Pathname] | bool]
          fields = Ipc::Serde.untagged_struct_variant(value, "FsScope::Scope", SCOPE_FIELDS,
            optional: %w[requireLiteralLeadingDot], aliases: { "requireLiteralLeadingDot" => ["require-literal-leading-dot"] },
            defaults:) do |field, raw|
            (field == "requireLiteralLeadingDot") ? Ipc::Serde.boolean(raw) : paths(raw)
          end
          allow = fields["allow"] #: Array[Pathname]
          deny = fields["deny"] #: Array[Pathname]
          require_literal_leading_dot = fields["requireLiteralLeadingDot"] #: bool?
          Scope.new(allow:, deny:, require_literal_leading_dot:)
        end
        private_class_method :scope

        def self.paths(value) # :nodoc:
          Utils::Config.sequence(value) { |path| Utils::Config.path(path) }
        end
        private_class_method :paths
      end

      # The asset protocol: whether it is on, and what it may serve.
      #
      # A page cannot read a file from disk by itself. The asset protocol,
      # <tt>asset://</tt>, serves one, but only from the paths its scope
      # allows.
      #
      # Tokra reads it now and acts on it with the asset protocol's own
      # plan (plan 054's inventory).
      #
      # Mirrors Tauri's <tt>AssetProtocolConfig</tt> (config.rs:2268-2286).
      #
      # === Example
      #
      #   security.asset_protocol.enable  #=> false
      class AssetProtocolConfig < Data.define(:scope, :enable)
        FIELDS = [
          Field.defaulted(:scope, "scope", -> (raw) { FsScope.deserialize(raw) }, FsScope::AllowedPaths.new(paths: [])),
          Field.defaulted(:enable, "enable", -> (raw) { Ipc::Serde.boolean(raw) }, false),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "AssetProtocolConfig", FIELDS))
        end

        # Takes either member as a keyword; one left out takes Tauri's
        # default.
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
