# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetComment: LogicalSize adapted from dpi 0.1.2 src/lib.rs

module Tokra
  # A size in logical pixels: physical pixels divided by the scale factor,
  # so the same on every display.
  #
  # Window#set_size, Window#set_min_size, and Window#set_max_size take one
  # or a PhysicalSize.
  #
  # Mirrors dpi's <tt>LogicalSize<P></tt> (src/lib.rs:537-611), which Tauri
  # re-exports as <tt>tauri::LogicalSize</tt>. A conversion answers Floats,
  # as PhysicalPosition explains.
  #
  # === Example
  #
  #   Tokra::LogicalSize.new(width: 400, height: 300).to_physical(2.0)
  #   #=> #<data Tokra::PhysicalSize width=800.0, height=600.0>
  class LogicalSize < Data.define(:width, :height)
    # The logical size of +physical+ at +scale_factor+, as
    # PhysicalSize#to_logical answers.
    #
    # Mirrors dpi's LogicalSize::from_physical.
    def self.from_physical(physical, scale_factor)
      physical.to_logical(scale_factor)
    end

    # This size in physical pixels at +scale_factor+: each side multiplied
    # by it. Raises ArgumentError for a scale factor
    # Dpi.validate_scale_factor rejects.
    #
    # Mirrors dpi's LogicalSize::to_physical.
    def to_physical(scale_factor)
      scale_factor = Dpi.assert_scale_factor(scale_factor)
      PhysicalSize.new(width: width.to_f * scale_factor, height: height.to_f * scale_factor)
    end
  end
end

# SPDX-SnippetEnd
