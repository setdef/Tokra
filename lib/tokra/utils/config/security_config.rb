# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: SecurityConfig adapted from tauri-utils src/config.rs:2576-2646
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # What your app's pages may do, and how they reach your code.
      #
      # A desktop app's pages run with more power than a web page: they
      # invoke your Ruby code. The security config limits that: the
      # Content Security Policy, a frozen JavaScript prototype, the asset
      # protocol's scope, the pattern invokes go through, the capabilities
      # granted, and the headers your responses carry.
      #
      # Tokra reads every key now. <tt>freezePrototype</tt> and the
      # pattern act once the builder takes a context; the policy, the
      # headers, the asset protocol, and the capabilities act with their
      # own plans (plan 054's inventory).
      #
      # Mirrors Tauri's <tt>SecurityConfig</tt> (config.rs:2576-2646).
      #
      # === Example
      #
      #   security = Tokra.generate_context.config.app.security
      #   security.freeze_prototype  #=> false
      #   security.pattern           #=> #<data Tokra::Utils::Config::PatternKind::Brownfield>
      class SecurityConfig < Data.define(
        :csp, :dev_csp, :freeze_prototype, :dangerous_disable_asset_csp_modification, :asset_protocol, :pattern,
        :capabilities, :headers
      )
        CSP = -> (raw) { Csp.deserialize(raw) } # :nodoc:
        private_constant :CSP

        FIELDS = [
          Field.option(:csp, "csp", CSP),
          Field.option(:dev_csp, "devCsp", CSP, aliases: %w[dev-csp]),
          Field.defaulted(:freeze_prototype, "freezePrototype", -> (raw) { Ipc::Serde.boolean(raw) }, false,
            aliases: %w[freeze-prototype]),
          Field.defaulted(:dangerous_disable_asset_csp_modification, "dangerousDisableAssetCspModification",
            -> (raw) { DisabledCspModificationKind.deserialize(raw) }, DisabledCspModificationKind::Flag.new(flag: false),
            aliases: %w[dangerous-disable-asset-csp-modification]),
          Field.defaulted(:asset_protocol, "assetProtocol", -> (raw) { AssetProtocolConfig.deserialize(raw) },
            AssetProtocolConfig.new, aliases: %w[asset-protocol]),
          Field.defaulted(:pattern, "pattern", -> (raw) { PatternKind.deserialize(raw) }, PatternKind::Brownfield.new),
          Field.defaulted(:capabilities, "capabilities",
            -> (raw) { Utils::Config.sequence(raw) { |entry| CapabilityEntry.deserialize(entry) } }, []),
          Field.defaulted(:headers, "headers", -> (raw) { HeaderConfig.deserialize(raw) }, nil, option: true),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "SecurityConfig", FIELDS))
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
