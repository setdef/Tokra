# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: CapabilityEntry adapted from tauri-utils src/config.rs:2648-2669
#   at vendor/tauri 9f0306fbc; its error words from serde-untagged 0.1.6
#   src/lib.rs:630-680, 920-966 (MIT OR Apache-2.0, David Tolnay)
#++

module Tokra
  module Utils
    module Config
      # One capability your app grants, by name or written out.
      #
      # A capability lists the commands a window's pages may invoke. The
      # config names one from your <tt>capabilities/</tt> directory, or
      # writes one inline.
      #
      # *Deviation*: Tauri reads an inline capability as its
      # <tt>Capability</tt> struct and refuses one that is not; Tokra keeps
      # it as its JSON, a Hash with String keys, and accepts any object,
      # until the capabilities plan types it (plan 054's inventory). Nothing
      # acts on capabilities before then.
      #
      # Mirrors Tauri's <tt>CapabilityEntry</tt> (config.rs:2648-2669).
      #
      # === Examples
      #
      #   # "capabilities": ["main-capability"]
      #   security.capabilities.first.name  #=> "main-capability"
      #
      #   # "capabilities": [{ "identifier": "inline", "permissions": [] }]
      #   security.capabilities.first.capability["identifier"]  #=> "inline"
      module CapabilityEntry
        # A capability written out, as its JSON.
        class Inlined < Data.define(:capability)
        end

        # A capability named by its identifier.
        class Reference < Data.define(:name)
        end

        # Reads +value+, a JSON value, as Tauri's own deserializer does,
        # through serde-untagged: a string names a capability, a map is one,
        # and anything else is <tt>expected a string or map</tt>.
        def self.deserialize(value) # :nodoc:
          case value
          when String then Reference.new(name: value)
          when Hash then Inlined.new(capability: value)
          else raise Ipc::CommandItem::Mismatch.invalid_type(value, "a string or map")
          end
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
