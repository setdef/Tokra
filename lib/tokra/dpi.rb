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

module Tokra
  module Dpi
    # The native <tt>[physical, x, y]</tt> for a LogicalPosition or a
    # PhysicalPosition, which the native layer turns into dpi's Position;
    # anything else raises TypeError.
    def self.position_dimensions(position) # :nodoc:
      case position
      when LogicalPosition then [false, Float(position.x), Float(position.y)]
      when PhysicalPosition then [true, Float(position.x), Float(position.y)]
      else
        raise TypeError,
          "wrong argument type #{position.class} (expected Tokra::LogicalPosition or Tokra::PhysicalPosition)"
      end
    end
  end
end

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: The winit contributors (dpi)
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: the serde forms of dpi 0.1.2's PixelUnit, Size, and
#   Position (src/lib.rs:333-338, 386-391, 462-467, 538-543, 614-619,
#   686-692, 741-747), each a derived Deserialize, as serde_json 1.0.145's
#   &Value drives it
#++

module Tokra
  module Dpi
    # The variants of dpi's PixelUnit, Size, and Position, in dpi's order.
    VARIANTS = %w[Physical Logical].freeze # :nodoc:

    # dpi's Size from a command argument's JSON value, as its derived
    # Deserialize reads serde_json's Value: an externally tagged enum of
    # two newtype variants, <tt>{"Physical": {"width", "height"}}</tt>, a
    # PhysicalSize of +u32+, or <tt>{"Logical": ...}</tt>, a LogicalSize
    # of +f64+, each struct a map or a sequence (dpi 0.1.2
    # src/lib.rs:686-692). Raises Ipc::CommandItem::Mismatch with serde's
    # words.
    def self.deserialize_size(value) # :nodoc:
      variant, content = Ipc::Serde.enum_variant(value, VARIANTS, newtype: VARIANTS)
      if variant == "Physical"
        fields = Ipc::Serde.struct_fields(content, "PhysicalSize", %w[width height]) { |_, raw| Ipc::CommandItem.integer(raw, "u32") }
        width = fields["width"] #: Integer
        height = fields["height"] #: Integer
        PhysicalSize.new(width:, height:)
      else
        fields = Ipc::Serde.struct_fields(content, "LogicalSize", %w[width height]) { |_, raw| Ipc::Serde.f64(raw) }
        width = fields["width"] #: Float
        height = fields["height"] #: Float
        LogicalSize.new(width:, height:)
      end
    end

    # dpi's Position, read as #deserialize_size reads a Size: a
    # PhysicalPosition of +i32+ or a LogicalPosition of +f64+ (dpi 0.1.2
    # src/lib.rs:741-747).
    def self.deserialize_position(value) # :nodoc:
      variant, content = Ipc::Serde.enum_variant(value, VARIANTS, newtype: VARIANTS)
      if variant == "Physical"
        fields = Ipc::Serde.struct_fields(content, "PhysicalPosition", %w[x y]) { |_, raw| Ipc::CommandItem.integer(raw, "i32") }
        x = fields["x"] #: Integer
        y = fields["y"] #: Integer
        PhysicalPosition.new(x:, y:)
      else
        fields = Ipc::Serde.struct_fields(content, "LogicalPosition", %w[x y]) { |_, raw| Ipc::Serde.f64(raw) }
        x = fields["x"] #: Float
        y = fields["y"] #: Float
        LogicalPosition.new(x:, y:)
      end
    end

    # dpi's PixelUnit: <tt>{"Physical": n}</tt>, a PhysicalUnit of +i32+,
    # or <tt>{"Logical": n}</tt>, a LogicalUnit of +f64+. Each unit is a
    # newtype struct, which serde_json reads as its one value (dpi 0.1.2
    # src/lib.rs:149-150, 243-244, 333-338; serde_json value/de.rs:880-900,
    # the <tt>&Value</tt> impl).
    def self.deserialize_pixel_unit(value) # :nodoc:
      variant, content = Ipc::Serde.enum_variant(value, VARIANTS, newtype: VARIANTS)
      if variant == "Physical"
        PhysicalUnit.new(value: Ipc::CommandItem.integer(content, "i32"))
      else
        LogicalUnit.new(value: Ipc::Serde.f64(content))
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
