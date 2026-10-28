# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetComment: LogicalUnit adapted from dpi 0.1.2 src/lib.rs

module Tokra
  # One length in logical pixels, such as a window's minimum width.
  #
  # WindowSizeConstraints holds one or a PhysicalUnit for each limit.
  #
  # Mirrors dpi's <tt>LogicalUnit<P></tt> (src/lib.rs:147-191), which
  # Tauri re-exports as <tt>tauri::LogicalUnit</tt>. dpi's is a tuple
  # struct; Ruby's Data needs a name, so the number is +value+ (plan 041,
  # decision 3). A conversion answers a Float, as PhysicalPosition
  # explains.
  #
  # === Example
  #
  #   Tokra::LogicalUnit.new(400).to_physical(2.0)  #=> #<data Tokra::PhysicalUnit value=800.0>
  class LogicalUnit < Data.define(:value)
    # The logical unit of PhysicalUnit#to_logical for +physical+ at
    # +scale_factor+.
    #
    # Mirrors dpi's LogicalUnit::from_physical.
    def self.from_physical(physical, scale_factor)
      physical.to_logical(scale_factor)
    end

    # This length in physical pixels at +scale_factor+: multiplied by it.
    # Raises ArgumentError for a scale factor Dpi.validate_scale_factor
    # rejects.
    #
    # Mirrors dpi's LogicalUnit::to_physical.
    def to_physical(scale_factor)
      scale_factor = Dpi.assert_scale_factor(scale_factor)
      PhysicalUnit.new(value: value.to_f * scale_factor)
    end

    ##
    # The largest logical unit, Float::MAX (dpi's LogicalUnit::MAX).
    MAX = new(value: Float::MAX)
    # The smallest logical unit, -Float::MAX (dpi's LogicalUnit::MIN).
    MIN = new(value: -Float::MAX)
    # A logical unit of zero (dpi's LogicalUnit::ZERO).
    ZERO = new(value: 0.0)
  end
end

# SPDX-SnippetEnd
