# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PreventOverflowMargin and PreventOverflowConfig adapted
#   from tauri-utils src/config.rs:1590-1618 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # How far a window keeps from the edges of the screen's work area.
      #
      # A window whose <tt>preventOverflow</tt> is on is moved and shrunk
      # to fit the work area. With a margin, the window plus the margin
      # fits, so the window stays clear of the edges by that much.
      #
      # Mirrors Tauri's <tt>PreventOverflowMargin</tt> (config.rs:1590-1600).
      #
      # === Example
      #
      #   margin = Tokra.generate_context.config.app.windows.first.prevent_overflow.margin
      #   margin.width  #=> 10
      class PreventOverflowMargin < Data.define(:width, :height)
        FIELDS = [
          Field.required(:width, "width", -> (raw) { Ipc::CommandItem.integer(raw, "u32") }),
          Field.required(:height, "height", -> (raw) { Ipc::CommandItem.integer(raw, "u32") }),
        ].freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "PreventOverflowMargin", FIELDS)) # steep:ignore UnresolvedOverloading
        end
      end

      # Whether a window keeps inside the screen's work area, and by how
      # much.
      #
      # A window placed or sized past the screen's edge can land partly
      # out of reach. <tt>preventOverflow</tt> moves it back: +true+ fits
      # it to the work area, and a margin fits it with room to spare. The
      # config writes either, so this enum has a variant for each.
      #
      # Mirrors Tauri's untagged <tt>PreventOverflowConfig</tt>
      # (config.rs:1602-1618).
      #
      # === Examples
      #
      #   # "preventOverflow": true
      #   window.prevent_overflow  #=> #<data Tokra::Utils::Config::PreventOverflowConfig::Enable enabled=true>
      #
      #   # "preventOverflow": { "width": 10, "height": 20 }
      #   window.prevent_overflow.margin.height  #=> 20
      module PreventOverflowConfig
        # Turns the work-area check on or off.
        class Enable < Data.define(:enabled)
        end

        # Turns the check on, with a margin.
        class Margin < Data.define(:margin)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum:
        # a boolean, then a margin.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "PreventOverflowConfig", [
            -> (raw) { Enable.new(enabled: Ipc::Serde.boolean(raw)) },
            -> (raw) { Margin.new(margin: PreventOverflowMargin.deserialize(raw)) },
          ])
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
