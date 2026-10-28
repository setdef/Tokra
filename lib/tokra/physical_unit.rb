# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetComment: PhysicalUnit adapted from dpi 0.1.2 src/lib.rs

module Tokra
  # One length in physical pixels, the display's own.
  #
  # WindowSizeConstraints holds one or a LogicalUnit for each limit; a
  # physical limit reaches the window rounded to whole pixels, as dpi
  # casts Tauri's <tt>PhysicalUnit<i32></tt>.
  #
  # Mirrors dpi's <tt>PhysicalUnit<P></tt> (src/lib.rs:241-282), which
  # Tauri re-exports as <tt>tauri::PhysicalUnit</tt>, with its number as
  # +value+, as LogicalUnit explains.
  #
  # === Example
  #
  #   Tokra::PhysicalUnit.new(800).to_logical(2.0)  #=> #<data Tokra::LogicalUnit value=400.0>
  class PhysicalUnit < Data.define(:value)
    # The physical unit of LogicalUnit#to_physical for +logical+ at
    # +scale_factor+.
    #
    # Mirrors dpi's PhysicalUnit::from_logical.
    def self.from_logical(logical, scale_factor)
      logical.to_physical(scale_factor)
    end

    # This length in logical pixels at +scale_factor+: divided by it.
    # Raises ArgumentError for a scale factor Dpi.validate_scale_factor
    # rejects.
    #
    # Mirrors dpi's PhysicalUnit::to_logical.
    def to_logical(scale_factor)
      scale_factor = Dpi.assert_scale_factor(scale_factor)
      LogicalUnit.new(value: value.to_f / scale_factor)
    end

    ##
    # dpi's PhysicalUnit::MAX, which dpi defines as a LogicalUnit of
    # Float::MAX, and so is this (src/lib.rs:247-248).
    MAX = LogicalUnit::MAX
    # dpi's PhysicalUnit::MIN, likewise a LogicalUnit.
    MIN = LogicalUnit::MIN
    # dpi's PhysicalUnit::ZERO, likewise a LogicalUnit.
    ZERO = LogicalUnit::ZERO
  end
end

# SPDX-SnippetEnd
