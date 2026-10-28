# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra's dpi values, which convert as the dpi crate's do (dpi 0.1.2
# src/lib.rs): logical times the scale factor is physical, and a scale
# factor validate_scale_factor rejects fails the conversion.
class TestDpi < Minitest::Test
  def test_a_logical_position_scales_up_to_a_physical_one
    physical = Tokra::LogicalPosition.new(x: 100, y: 50).to_physical(2.0)

    assert_equal Tokra::PhysicalPosition.new(x: 200.0, y: 100.0), physical
  end

  def test_a_physical_position_scales_down_to_a_logical_one
    logical = Tokra::PhysicalPosition.new(x: 300, y: 150).to_logical(1.5)

    assert_equal Tokra::LogicalPosition.new(x: 200.0, y: 100.0), logical
  end

  def test_a_logical_size_scales_up_to_a_physical_one
    physical = Tokra::LogicalSize.new(width: 400, height: 300).to_physical(2.0)

    assert_equal Tokra::PhysicalSize.new(width: 800.0, height: 600.0), physical
  end

  def test_a_physical_size_scales_down_to_a_logical_one
    logical = Tokra::PhysicalSize.new(width: 800, height: 600).to_logical(2.0)

    assert_equal Tokra::LogicalSize.new(width: 400.0, height: 300.0), logical
  end

  # Ruby picks no pixel type, so a conversion keeps dpi's f64 answer.
  def test_conversions_answer_floats_without_rounding
    physical = Tokra::LogicalSize.new(width: 3, height: 5).to_physical(1.25)

    assert_equal [3.75, 6.25], [physical.width, physical.height]
    assert_kind_of Float, Tokra::PhysicalPosition.new(x: 4, y: 4).to_logical(2).x
  end

  def test_from_builds_from_the_other_kind
    assert_equal Tokra::PhysicalSize.new(width: 20.0, height: 10.0),
      Tokra::PhysicalSize.from_logical(Tokra::LogicalSize.new(width: 10, height: 5), 2.0)
    assert_equal Tokra::LogicalSize.new(width: 5.0, height: 2.5),
      Tokra::LogicalSize.from_physical(Tokra::PhysicalSize.new(width: 10, height: 5), 2.0)
    assert_equal Tokra::PhysicalPosition.new(x: 20.0, y: 10.0),
      Tokra::PhysicalPosition.from_logical(Tokra::LogicalPosition.new(x: 10, y: 5), 2.0)
    assert_equal Tokra::LogicalPosition.new(x: 5.0, y: 2.5),
      Tokra::LogicalPosition.from_physical(Tokra::PhysicalPosition.new(x: 10, y: 5), 2.0)
  end

  def test_validate_scale_factor_accepts_only_positive_normal_numbers
    assert Tokra::Dpi.validate_scale_factor(1.0)
    assert Tokra::Dpi.validate_scale_factor(2)
    assert Tokra::Dpi.validate_scale_factor(Float::MIN)
    [0.0, -0.0, -1.0, Float::MIN / 2, Float::INFINITY, Float::NAN].each do |factor|
      refute Tokra::Dpi.validate_scale_factor(factor), factor.inspect
    end
  end

  # dpi asserts validate_scale_factor and panics with its text.
  def test_every_conversion_refuses_an_invalid_scale_factor_in_dpis_words
    conversions = [
      -> { Tokra::LogicalPosition.new(x: 1, y: 1).to_physical(0.0) },
      -> { Tokra::PhysicalPosition.new(x: 1, y: 1).to_logical(-2.0) },
      -> { Tokra::LogicalSize.new(width: 1, height: 1).to_physical(Float::NAN) },
      -> { Tokra::PhysicalSize.new(width: 1, height: 1).to_logical(Float::INFINITY) },
    ]
    conversions.each do |conversion|
      error = assert_raises(ArgumentError, &conversion)
      assert_equal "assertion failed: validate_scale_factor(scale_factor)", error.message
    end
  end

  def test_values_are_shareable
    [
      Tokra::LogicalPosition.new(x: 1, y: 2),
      Tokra::PhysicalSize.new(width: 1, height: 2),
      Tokra::LogicalSize.new(width: 1, height: 2),
      Tokra::PhysicalRect.new(position: Tokra::PhysicalPosition.new(x: 0, y: 0),
        size: Tokra::PhysicalSize.new(width: 1, height: 1)),
      Tokra::Theme::Dark,
      Tokra::CursorIcon::Wait,
      Tokra::UserAttentionType::Critical,
      Tokra::ResizeDirection::West,
    ].each { |value| assert Ractor.shareable?(value), value.inspect }
  end

  # Tauri's closed enums: only their own variants, named as Tauri names
  # them (tauri-utils src/lib.rs:218-226, tauri-runtime src/lib.rs:80-117,
  # src/window.rs:100-159).
  def test_the_enums_have_tauris_variants_and_no_others
    {
      Tokra::Theme => %w[Light Dark],
      Tokra::UserAttentionType => %w[Critical Informational],
      Tokra::ResizeDirection => %w[East North NorthEast NorthWest South SouthEast SouthWest West],
    }.each do |enum, names|
      assert_equal names.sort, enum.constants.map(&:to_s).sort
      names.each { |name| assert_equal name, enum.const_get(name).name }
      assert_raises(NoMethodError) { enum.new(name: "Other") }
    end
    assert_equal 35, Tokra::CursorIcon.constants.size
    assert_equal "NwseResize", Tokra::CursorIcon::NwseResize.name
  end

  def test_a_logical_unit_scales_up_to_a_physical_one
    assert_equal Tokra::PhysicalUnit.new(800.0), Tokra::LogicalUnit.new(400).to_physical(2.0)
    assert_equal Tokra::PhysicalUnit.new(800.0), Tokra::PhysicalUnit.from_logical(Tokra::LogicalUnit.new(400), 2.0)
  end

  def test_a_physical_unit_scales_down_to_a_logical_one
    assert_equal Tokra::LogicalUnit.new(400.0), Tokra::PhysicalUnit.new(600).to_logical(1.5)
    assert_equal Tokra::LogicalUnit.new(400.0), Tokra::LogicalUnit.from_physical(Tokra::PhysicalUnit.new(600), 1.5)
  end

  def test_a_unit_conversion_rejects_what_dpi_rejects
    assert_raises(ArgumentError) { Tokra::LogicalUnit.new(1).to_physical(0.0) }
    assert_raises(ArgumentError) { Tokra::PhysicalUnit.new(1).to_logical(Float::NAN) }
  end

  # dpi defines PhysicalUnit's MAX, MIN, and ZERO as LogicalUnits
  # (src/lib.rs:247-252).
  def test_the_unit_constants_are_dpis
    assert_equal Tokra::LogicalUnit.new(Float::MAX), Tokra::LogicalUnit::MAX
    assert_equal Tokra::LogicalUnit.new(-Float::MAX), Tokra::LogicalUnit::MIN
    assert_equal Tokra::LogicalUnit.new(0.0), Tokra::LogicalUnit::ZERO
    assert_same Tokra::LogicalUnit::MAX, Tokra::PhysicalUnit::MAX
    assert_same Tokra::LogicalUnit::MIN, Tokra::PhysicalUnit::MIN
    assert_same Tokra::LogicalUnit::ZERO, Tokra::PhysicalUnit::ZERO
  end

  # Tauri's Default leaves every limit None (tauri-runtime window.rs:209).
  def test_size_constraints_default_to_no_limits
    constraints = Tokra::WindowSizeConstraints.new

    assert_equal [nil, nil, nil, nil],
      [constraints.min_width, constraints.min_height, constraints.max_width, constraints.max_height]
  end

  def test_size_constraints_take_either_unit_and_nothing_else
    constraints = Tokra::WindowSizeConstraints.new(min_width: Tokra::LogicalUnit.new(1),
      max_height: Tokra::PhysicalUnit.new(2))

    assert_equal Tokra::LogicalUnit.new(1), constraints.min_width
    assert_equal Tokra::PhysicalUnit.new(2), constraints.max_height
    error = assert_raises(TypeError) { Tokra::WindowSizeConstraints.new(max_width: 300) }
    assert_includes error.message, "Integer"
  end
end
