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

  # Rust's str::trim strips Unicode White_Space and keeps NUL
  # (config.rs:1471; core str::trim), where Ruby's strip strips ASCII
  # whitespace and NUL.
  def test_from_str_trims_unicode_white_space_and_keeps_nul
    white = Tokra::Color.new(255, 255, 255, 255)

    assert_equal white, Tokra::Color.from_str("\u00A0#fff")
    assert_equal white, Tokra::Color.from_str("\u3000#fff\u3000")
    assert_equal white, Tokra::Color.from_str("\n#fff\t")
    ["\0#fff", "#fff\0"].each do |text|
      error = assert_raises(ArgumentError, text.inspect) { Tokra::Color.from_str(text) }
      assert_equal Tokra::Color::INVALID_LENGTH, error.message, text.inspect
    end
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

  # A pair of bytes that splits a character panics Tauri's slice
  # (config.rs:1483-1486); Tokra answers u8::from_str_radix's message for
  # text that is not hex instead.
  def test_from_str_rejects_a_pair_that_splits_a_character_as_text_that_is_not_hex
    ["a\u00E9123", "\u20AC"].each do |text|
      error = assert_raises(ArgumentError, text.inspect) { Tokra::Color.from_str(text) }
      assert_equal "invalid digit found in string", error.message, text.inspect
    end
  end

  # Color's Deserialize reads the untagged InnerColor (config.rs:1492-1536):
  # a string, three u8s, four, or a map whose alpha defaults to 255.
  private def mismatch(&)
    assert_raises(Tokra::Ipc::CommandItem::Mismatch, &).message
  end

  UNTAGGED = "data did not match any variant of untagged enum InnerColor"

  def test_deserialize_reads_each_of_the_four_forms
    assert_equal Tokra::Color.new(255, 0, 170, 255), Tokra::Color.deserialize("#f0a")
    assert_equal Tokra::Color.new(1, 2, 3, 255), Tokra::Color.deserialize([1, 2, 3])
    assert_equal Tokra::Color.new(1, 2, 3, 4), Tokra::Color.deserialize([1, 2, 3, 4])
    assert_equal Tokra::Color.new(1, 2, 3, 4),
      Tokra::Color.deserialize({ "red" => 1, "green" => 2, "blue" => 3, "alpha" => 4 })
  end

  # default_alpha (config.rs:1492-1494); the map ignores other keys.
  def test_deserialize_defaults_a_maps_alpha_to_opaque
    assert_equal Tokra::Color.new(1, 2, 3, 255), Tokra::Color.deserialize({ "red" => 1, "green" => 2, "blue" => 3 })
    assert_equal Tokra::Color.new(1, 2, 3, 255),
      Tokra::Color.deserialize({ "red" => 1, "green" => 2, "blue" => 3, "other" => "x" })
  end

  # The string variant reads, then FromStr's error is serde's custom one.
  def test_deserialize_rejects_bad_text_with_from_strs_message
    assert_equal Tokra::Color::INVALID_LENGTH, mismatch { Tokra::Color.deserialize("#ff") }
    assert_equal "invalid digit found in string", mismatch { Tokra::Color.deserialize("#gg0000") }
  end

  # Every other failure is the untagged enum's one message.
  def test_deserialize_rejects_anything_else_as_the_untagged_enum
    [
      [1, 2],
      [256, 0, 0],
      [1, 2, 3, -1],
      [1, 2, 3, 4, 5],
      [1.0, 2, 3],
      ["1", 2, 3],
      { "red" => 1, "green" => 2 },
      { "red" => 256, "green" => 0, "blue" => 0 },
      { "red" => 1, "green" => 2, "blue" => 3, "alpha" => nil },
      { "red" => 1.5, "green" => 2, "blue" => 3 },
      1,
      nil,
      true,
    ].each do |value|
      assert_equal UNTAGGED, mismatch { Tokra::Color.deserialize(value) }, value.inspect
    end
  end
end
