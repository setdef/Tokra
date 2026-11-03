# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: CspDirectiveSources, Csp, and DisabledCspModificationKind
#   adapted from tauri-utils src/config.rs:2066-2215 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The sources one Content Security Policy directive allows.
      #
      # A directive such as <tt>img-src</tt> lists the places a page may
      # load from. The config writes the list as one string, as a CSP
      # header writes it, or as an array of sources, so this enum has a
      # variant for each.
      #
      # Mirrors Tauri's untagged <tt>CspDirectiveSources</tt>
      # (config.rs:2066-2075).
      #
      # === Example
      #
      #   # "img-src": ["'self'", "asset:"]
      #   sources  #=> #<data Tokra::Utils::Config::CspDirectiveSources::List sources=["'self'", "asset:"]>
      module CspDirectiveSources
        # The sources as one string, separated by spaces.
        class Inline < Data.define(:sources)
        end

        # The sources as a list.
        class List < Data.define(:sources)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "CspDirectiveSources", [
            -> (raw) { Inline.new(sources: Ipc::Serde.string(raw)) },
            -> (raw) { List.new(sources: Utils::Config.sequence(raw) { |source| Ipc::Serde.string(source) }) },
          ])
        end
      end

      # A Content Security Policy for your app's pages.
      #
      # A policy names where a page may load scripts, styles, and images
      # from, so injected content cannot run. The config writes it as the
      # header's own string, or as an object of directive to sources.
      #
      # Tokra reads it now, and acts on it with the plan that embeds and
      # serves your frontend's assets, since the policy rides on them
      # (plan 054's inventory).
      #
      # Mirrors Tauri's untagged <tt>Csp</tt> (config.rs:2112-2121).
      #
      # === Examples
      #
      #   # "csp": "default-src 'self'"
      #   security.csp  #=> #<data Tokra::Utils::Config::Csp::Policy policy="default-src 'self'">
      #
      #   # "csp": { "default-src": "'self'" }
      #   security.csp.directives.keys  #=> ["default-src"]
      module Csp
        # The policy as a header writes it.
        class Policy < Data.define(:policy)
        end

        # The policy as a Hash of directive name to CspDirectiveSources.
        class DirectiveMap < Data.define(:directives)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "Csp", [
            -> (raw) { Policy.new(policy: Ipc::Serde.string(raw)) },
            -> (raw) { DirectiveMap.new(directives: Utils::Config.map(raw) { |sources| CspDirectiveSources.deserialize(sources) }) },
          ])
        end
      end

      # Which directives Tauri may not touch when it adds its own sources
      # to your policy.
      #
      # Tauri adds nonces and hashes to your policy so its own scripts
      # run. An app that sets every source by hand turns that off, for all
      # directives with +true+ or for some with their names.
      #
      # Mirrors Tauri's untagged <tt>DisabledCspModificationKind</tt>
      # (config.rs:2182-2215).
      #
      # === Example
      #
      #   # "dangerousDisableAssetCspModification": ["style-src"]
      #   security.dangerous_disable_asset_csp_modification.directives  #=> ["style-src"]
      module DisabledCspModificationKind
        # Every directive, or none.
        class Flag < Data.define(:flag)
        end

        # The directives named.
        class List < Data.define(:directives)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "DisabledCspModificationKind", [
            -> (raw) { Flag.new(flag: Ipc::Serde.boolean(raw)) },
            -> (raw) { List.new(directives: Utils::Config.sequence(raw) { |directive| Ipc::Serde.string(directive) }) },
          ])
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
