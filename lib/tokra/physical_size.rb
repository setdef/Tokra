# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetComment: PhysicalSize adapted from dpi 0.1.2 src/lib.rs

module Tokra
  # A size in physical pixels: the display's own pixels.
  #
  # Window#inner_size and Window#outer_size answer one, and
  # Window#set_size takes one or a LogicalSize.
  #
  # Mirrors dpi's <tt>PhysicalSize<P></tt> (src/lib.rs:613-684), which
  # Tauri re-exports as <tt>tauri::PhysicalSize</tt>. A conversion answers
  # Floats, as PhysicalPosition explains.
  #
  # === Example
  #
  #   Tokra::PhysicalSize.new(width: 800, height: 600).to_logical(2.0)
  #   #=> #<data Tokra::LogicalSize width=400.0, height=300.0>
  class PhysicalSize < Data.define(:width, :height)
    # The physical size of +logical+ at +scale_factor+, as
    # LogicalSize#to_physical answers.
    #
    # Mirrors dpi's PhysicalSize::from_logical.
    def self.from_logical(logical, scale_factor)
      logical.to_physical(scale_factor)
    end

    # This size in logical pixels at +scale_factor+: each side divided by
    # it. Raises ArgumentError for a scale factor Dpi.validate_scale_factor
    # rejects.
    #
    # Mirrors dpi's PhysicalSize::to_logical.
    def to_logical(scale_factor)
      scale_factor = Dpi.assert_scale_factor(scale_factor)
      LogicalSize.new(width: width.to_f / scale_factor, height: height.to_f / scale_factor)
    end
  end
end

# SPDX-SnippetEnd
