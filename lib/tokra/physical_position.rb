# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetComment: PhysicalPosition adapted from dpi 0.1.2 src/lib.rs

module Tokra
  # A position in physical pixels: the display's own pixels.
  #
  # Window#inner_position and Window#outer_position answer one, and
  # Window#set_position takes one or a LogicalPosition. +x+ and +y+ are
  # Integers when the platform reports them, and Floats when a conversion
  # made them.
  #
  # Mirrors dpi's <tt>PhysicalPosition<P></tt> (src/lib.rs:461-535), which
  # Tauri re-exports as <tt>tauri::PhysicalPosition</tt>. Ruby has no type
  # parameter to pick the pixel type, so a conversion answers the Float it
  # computed, dpi's answer for <tt>f64</tt>; round it for dpi's
  # <tt>i32</tt>.
  #
  # === Example
  #
  #   Tokra::PhysicalPosition.new(x: 200, y: 100).to_logical(2.0)
  #   #=> #<data Tokra::LogicalPosition x=100.0, y=50.0>
  class PhysicalPosition < Data.define(:x, :y)
    # The physical position of +logical+ at +scale_factor+, as
    # LogicalPosition#to_physical answers.
    #
    # Mirrors dpi's PhysicalPosition::from_logical.
    def self.from_logical(logical, scale_factor)
      logical.to_physical(scale_factor)
    end

    # This position in logical pixels at +scale_factor+: each coordinate
    # divided by it. Raises ArgumentError for a scale factor
    # Dpi.validate_scale_factor rejects.
    #
    # Mirrors dpi's PhysicalPosition::to_logical.
    def to_logical(scale_factor)
      scale_factor = Dpi.assert_scale_factor(scale_factor)
      LogicalPosition.new(x: x.to_f / scale_factor, y: y.to_f / scale_factor)
    end
  end
end

# SPDX-SnippetEnd
