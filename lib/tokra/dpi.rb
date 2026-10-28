# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetComment: validate_scale_factor adapted from dpi 0.1.2 src/lib.rs

module Tokra
  # Logical and physical pixels, and the scale factor between them.
  #
  # A window on a high-density display has more physical pixels than
  # logical ones: at a scale factor of 2.0, a 400 by 300 logical window is
  # 800 by 600 physical pixels. Tokra::LogicalPosition, LogicalSize,
  # PhysicalPosition, and PhysicalSize name each kind, and each converts to
  # the other given a scale factor, such as Window#scale_factor or
  # Monitor#scale_factor answers.
  #
  # Mirrors the dpi crate Tauri re-exports as <tt>tauri::dpi</tt>
  # (tauri-runtime src/dpi.rs:5; dpi 0.1.2 src/lib.rs).
  module Dpi
    # The message dpi's assertion panics with for a scale factor it
    # rejects; here ArgumentError carries it.
    INVALID_SCALE_FACTOR = "assertion failed: validate_scale_factor(scale_factor)"

    # Whether +scale_factor+ can convert between logical and physical
    # pixels: positive and normal, so neither zero, subnormal, infinite,
    # nor NaN.
    #
    # Mirrors dpi's validate_scale_factor (src/lib.rs:142-145).
    #
    # === Example
    #
    #   Tokra::Dpi.validate_scale_factor(2.0)  #=> true
    #   Tokra::Dpi.validate_scale_factor(0.0)  #=> false
    def self.validate_scale_factor(scale_factor)
      scale_factor = scale_factor.to_f
      scale_factor.finite? && scale_factor >= Float::MIN
    end

    # Raises ArgumentError unless +scale_factor+ is valid, as each dpi
    # conversion asserts.
    def self.assert_scale_factor(scale_factor)
      raise ArgumentError, INVALID_SCALE_FACTOR unless validate_scale_factor(scale_factor)

      scale_factor.to_f
    end
  end
end

# SPDX-SnippetEnd
