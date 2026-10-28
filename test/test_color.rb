# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Color, Tauri's Color(u8, u8, u8, u8) and its FromStr
# (tauri-utils src/config.rs:1415-1490).
class TestColor < Minitest::Test
  def test_a_color_holds_four_components
    color = Tokra::Color.new(1, 2, 3, 4)

    assert_equal [1, 2, 3, 4], [color.red, color.green, color.blue, color.alpha]
    assert_equal color, Tokra::Color.new(red: 1, green: 2, blue: 3, alpha: 4)
  end

  def test_a_component_outside_a_byte_raises_range_error
    assert_raises(RangeError) { Tokra::Color.new(256, 0, 0, 0) }
    assert_raises(RangeError) { Tokra::Color.new(0, -1, 0, 0) }
  end

  def test_a_component_that_is_not_an_integer_raises_type_error
    assert_raises(TypeError) { Tokra::Color.new(0, 0, 1.5, 0) }
    assert_raises(TypeError) { Tokra::Color.new(0, 0, 0, "ff") }
  end

  def test_from_str_reads_six_and_eight_digits
    assert_equal Tokra::Color.new(0x12, 0x34, 0x56, 255), Tokra::Color.from_str("#123456")
    assert_equal Tokra::Color.new(0x12, 0x34, 0x56, 0x78), Tokra::Color.from_str("12345678")
    assert_equal Tokra::Color.new(0xAB, 0xCD, 0xEF, 255), Tokra::Color.from_str("abcdef")
  end

  # Three digits double each one and add an opaque alpha.
  def test_from_str_doubles_three_digits
    assert_equal Tokra::Color.new(0xFF, 0x00, 0xAA, 0xFF), Tokra::Color.from_str("#f0a")
  end

  # Tauri trims, then strips a #; without one, it reads the untrimmed
  # text (config.rs:1471).
  def test_from_str_trims_only_around_a_hash
    assert_equal Tokra::Color.new(255, 255, 255, 255), Tokra::Color.from_str("  #fff ")
    error = assert_raises(ArgumentError) { Tokra::Color.from_str(" fff") }
    assert_equal Tokra::Color::INVALID_LENGTH, error.message
  end

  def test_from_str_rejects_other_lengths_in_tauris_words
    error = assert_raises(ArgumentError) { Tokra::Color.from_str("#ffff") }
    assert_equal "Invalid hex color length, must be either 3, 6 or 8, for example: #fff, #ffffff, or #ffffffff",
      error.message
  end

  # u8::from_str_radix's ParseIntError text; it accepts a leading +.
  def test_from_str_rejects_a_digit_that_is_not_hex_as_rust_does
    error = assert_raises(ArgumentError) { Tokra::Color.from_str("#gg0000") }
    assert_equal "invalid digit found in string", error.message
    assert_raises(ArgumentError) { Tokra::Color.from_str("#-10000") }
    assert_equal Tokra::Color.new(15, 0, 0, 255), Tokra::Color.from_str("+f0000")
  end
end
