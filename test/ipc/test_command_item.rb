# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Ipc::CommandItem and Tokra::Ipc::Unexpected: one argument
# read as Tauri's CommandItem deserializer reads it (ipc/command.rs), with
# serde_json's messages.
class TestCommandItem < Minitest::Test
  CommandItem = Tokra::Ipc::CommandItem
  Unexpected = Tokra::Ipc::Unexpected

  private def item(payload, key = "shortcuts")
    CommandItem.new(name: "register", key:, payload:)
  end

  # CommandItem raises Tauri's Error::InvalidArgs, so a plugin rescues
  # exactly the argument failures (plan 026, decision 1).
  private def error(&)
    assert_raises(Tokra::Error::InvalidArgs, &).message
  end

  def test_a_string_reads_as_it_is
    assert_equal "F19", item({ "shortcut" => "F19" }, "shortcut").string
  end

  def test_strings_read_a_sequence_of_strings
    assert_equal ["F17", "F18"], item({ "shortcuts" => ["F17", "F18"] }).strings
    assert_equal [], item({ "shortcuts" => [] }).strings
  end

  # command.rs:97-102, wrapped in InvalidArgs (error.rs:59-60).
  def test_a_missing_key_rejects_with_tauris_message
    assert_equal "invalid args `shortcuts` for command `register`: command register missing required key shortcuts",
      error { item({}).strings }
  end

  def test_a_wrong_type_names_what_arrived
    prefix = "invalid args `shortcuts` for command `register`: invalid type:"
    assert_equal "#{prefix} string \"F19\", expected a sequence", error { item({ "shortcuts" => "F19" }).strings }
    assert_equal "#{prefix} null, expected a sequence", error { item({ "shortcuts" => nil }).strings }
    assert_equal "#{prefix} integer `1`, expected a string", error { item({ "shortcuts" => ["F19", 1] }).strings }
    assert_equal "#{prefix} map, expected a string", error { item({ "shortcuts" => {} }).string }
  end

  # Any argument reads through the block, whose Mismatch becomes
  # InvalidArgs; a missing key is serde_json's custom error
  # (command.rs:60-70, 97-102).
  def test_deserialize_yields_the_value_and_wraps_a_mismatch
    assert_equal 2, item({ "count" => 1 }, "count").deserialize { |value| value + 1 }
    assert_equal "invalid args `count` for command `register`: invalid type: integer `1`, expected a boolean",
      error { item({ "count" => 1 }, "count").deserialize { |value| raise CommandItem::Mismatch.invalid_type(value, "a boolean") } }
    assert_equal "invalid args `count` for command `register`: command register missing required key count",
      error { item({}, "count").deserialize { flunk "a missing key yields nothing" } }
    # A null is present, so a type that is not an Option gets to see it
    # (command.rs:97-102).
    assert_equal "invalid args `count` for command `register`: invalid type: null, expected a boolean",
      error { item({ "count" => nil }, "count").deserialize { |value| raise CommandItem::Mismatch.invalid_type(value, "a boolean") } }
  end

  # An Option is None for a missing key or null, and otherwise reads the
  # value (command.rs:134-145, serde_json value/de.rs deserialize_option).
  def test_deserialize_option_reads_a_missing_key_or_null_as_nil
    assert_nil item({}, "label").deserialize_option { flunk "a missing key yields nothing" }
    assert_nil item({ "label" => nil }, "label").deserialize_option { flunk "null yields nothing" }
    assert_equal "A", item({ "label" => "a" }, "label").deserialize_option(&:upcase)
    assert_equal "invalid args `label` for command `register`: invalid value: integer `3`, expected u8",
      error { item({ "label" => 3 }, "label").deserialize_option { raise CommandItem::Mismatch, "invalid value: integer `3`, expected u8" } }
  end

  # serde_json's descriptions (value/de.rs:1395-1404, error.rs
  # JsonUnexpected): floats as ryu prints them, integers past u64 as
  # floats, strings quoted as Rust's Debug quotes them.
  def test_values_are_described_as_serde_json_describes_them
    assert_equal "null", Unexpected.describe(nil)
    assert_equal "boolean `false`", Unexpected.describe(false)
    assert_equal "integer `-3`", Unexpected.describe(-3)
    assert_equal "floating point `1.5`", Unexpected.describe(1.5)
    assert_equal "floating point `1e16`", Unexpected.describe(1e16)
    assert_equal "floating point `0.00001`", Unexpected.describe(0.00001)
    assert_equal "floating point `1.8446744073709552e19`", Unexpected.describe(2 ** 64)
    assert_equal "string \"a\\tb\\u{7f}\\0\"", Unexpected.describe("a\tb\u007f\u0000")
    {
      0.0 => "0.0",
      -2.5 => "-2.5",
      100.0 => "100.0",
      1e-7 => "1e-7",
      1.5e-7 => "1.5e-7",
      1_234_567_890_123_456.0 => "1234567890123456.0",
      12_345_678_901_234_567.0 => "1.2345678901234568e16",
    }.each { |float, text| assert_equal "floating point `#{text}`", Unexpected.describe(float) }
    # The plan 024 oracle's answer for grapheme extenders, format and
    # private-use characters, and separators.
    assert_equal 'string "a\u{301}\u{200b}\u{85}\u{a0}\u{2028} \u{ad}\u{e000}x\u{200c}\u{1f}\u{7f}"',
      Unexpected.describe("a\u0301\u200b\u0085\u00a0\u2028 \u00ad\ue000x\u200c\u001f\u007f")
    assert_equal "sequence", Unexpected.describe([])
    assert_equal "map", Unexpected.describe({})
  end
end
