# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PatternKind adapted from tauri-utils src/config.rs:2671-2685
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # How your pages reach your Ruby code: directly, or through an
      # isolation app.
      #
      # By default a page's invoke goes straight to Tokra, the brownfield
      # pattern. The isolation pattern runs every message through a small
      # app of your own in a sandboxed frame first, so a compromised page
      # cannot forge one. The config writes the choice as
      # <tt>{ "use": "brownfield" }</tt> or <tt>{ "use": "isolation",
      # "options": { "dir": "..." } }</tt>.
      #
      # Tokra builds the brownfield pattern. A config's isolation reads as
      # brownfield until an isolation plan builds it, as Tauri without its
      # <tt>isolation</tt> feature reads it (plan 054, decision 21).
      #
      # Mirrors Tauri's adjacently tagged <tt>PatternKind</tt>
      # (config.rs:2671-2685).
      #
      # === Example
      #
      #   security.pattern  #=> #<data Tokra::Utils::Config::PatternKind::Brownfield>
      module PatternKind
        # Pages invoke Tokra directly.
        Brownfield = Data.define

        # Pages invoke through the isolation app in +dir+, a Pathname.
        class Isolation < Data.define(:dir)
        end

        # Reads +value+, a JSON value, as serde reads the enum: tagged
        # <tt>use</tt>, with its content under <tt>options</tt>.
        def self.deserialize(value) # :nodoc:
          variant, dir = Ipc::Serde.adjacently_tagged(value, "use", "options", "PatternKind", %w[brownfield isolation],
            unit: %w[brownfield]) do |name, raw|
            if name == "brownfield"
              Ipc::Serde.untagged_unit(raw, "PatternKind::Brownfield")
            else
              Ipc::Serde.untagged_struct_variant(raw, "PatternKind::Isolation", %w[dir]) { |_field, path| Utils::Config.path(path) }
                .fetch("dir")
            end
          end
          (variant == "brownfield") ? Brownfield.new : Isolation.new(dir:)
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
