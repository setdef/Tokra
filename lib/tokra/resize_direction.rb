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

    close
  end
end

# SPDX-SnippetEnd
