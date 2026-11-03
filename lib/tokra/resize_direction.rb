# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: ResizeDirection adapted from tauri-runtime/src/lib.rs

module Tokra
  # The edge or corner Window#start_resize_dragging resizes from.
  #
  # These eight are the only directions, as in Tauri's enum, so
  # ResizeDirection.new is private.
  #
  # Mirrors Tauri's ResizeDirection (tauri-runtime src/lib.rs:106-117).
  #
  # === Example
  #
  #   window.start_resize_dragging(Tokra::ResizeDirection::SouthEast)
  class ResizeDirection < Data.define(:name)
    extend ClosedEnum

    ##
    # The right edge.
    East = new(name: "East")
    # The top edge.
    North = new(name: "North")
    # The top-right corner.
    NorthEast = new(name: "NorthEast")
    # The top-left corner.
    NorthWest = new(name: "NorthWest")
    # The bottom edge.
    South = new(name: "South")
    # The bottom-right corner.
    SouthEast = new(name: "SouthEast")
    # The bottom-left corner.
    SouthWest = new(name: "SouthWest")
    # The left edge.
    West = new(name: "West")

    # The directions in Tauri's order, which serde's errors list.
    VARIANTS = [East, North, NorthEast, NorthWest, South, SouthEast, SouthWest, West].freeze
    private_constant :VARIANTS

    # The direction a command argument names, as the derived Deserialize
    # reads it: a unit variant by Tauri's name, <tt>"East"</tt> and so on
    # (tauri-runtime src/lib.rs:105-116; Ipc::Serde.unit_variant).
    def self.deserialize(value) # :nodoc:
      directions = VARIANTS.to_h { |direction| [direction.name, direction] }
      directions.fetch(Ipc::Serde.unit_variant(value, directions.keys))
    end

    close
  end
end

# SPDX-SnippetEnd
