# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetComment: LogicalPosition adapted from dpi 0.1.2 src/lib.rs

module Tokra
  # A position in logical pixels: physical pixels divided by the scale
  # factor, so the same on every display.
  #
  # Window#set_position and Window#set_cursor_position take one or a
  # PhysicalPosition.
  #
  # Mirrors dpi's <tt>LogicalPosition<P></tt> (src/lib.rs:385-459), which
  # Tauri re-exports as <tt>tauri::LogicalPosition</tt>. A conversion
  # answers Floats, as PhysicalPosition explains.
  #
  # === Example
  #
  #   Tokra::LogicalPosition.new(x: 100, y: 50).to_physical(2.0)
  #   #=> #<data Tokra::PhysicalPosition x=200.0, y=100.0>
  class LogicalPosition < Data.define(:x, :y)
    # The logical position of +physical+ at +scale_factor+, as
    # PhysicalPosition#to_logical answers.
    #
    # Mirrors dpi's LogicalPosition::from_physical.
    def self.from_physical(physical, scale_factor)
      physical.to_logical(scale_factor)
    end

    # This position in physical pixels at +scale_factor+: each coordinate
    # multiplied by it. Raises ArgumentError for a scale factor
    # Dpi.validate_scale_factor rejects.
    #
    # Mirrors dpi's LogicalPosition::to_physical.
    def to_physical(scale_factor)
      scale_factor = Dpi.assert_scale_factor(scale_factor)
      PhysicalPosition.new(x: x.to_f * scale_factor, y: y.to_f * scale_factor)
    end
  end
end

# SPDX-SnippetEnd
