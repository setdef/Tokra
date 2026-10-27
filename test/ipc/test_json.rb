# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Ipc::Json, the port of serde_json's from_slice::<Value>.
#
# Every expectation here is what serde_json 1.0.145, with the raw_value
# feature Tauri enables, gives for the same bytes: Plan 032's oracle ran
# serde_json itself on each input.
class TestIpcJson < Minitest::Test
  private def assert_rejects(message, input)
    error = assert_raises(Tokra::Ipc::Json::Error, input.inspect) { Tokra::Ipc::Json.parse(input) }
    assert_equal message, error.message, input.inspect
  end

  private def float_bits(float)
    [float].pack("G").unpack1("H*")
  end

  def test_error_is_a_tokra_error
    assert_operator Tokra::Ipc::Json::Error, :<, Tokra::Error
  end

  def test_reads_every_kind_of_value
    assert_equal(
      { "a" => [nil, true, false, "x\n\u0041/", 1, -2, 2.5, {}] },
      Tokra::Ipc::Json.parse(' {"a" : [null, true, false, "x\\n\\u0041\\/", 1, -2, 2.5e0, {}]} ')
    )
    assert_equal "\"\\/\b\f\n\r\t", Tokra::Ipc::Json.parse('"\\"\\\\\\/\\b\\f\\n\\r\\t"')
    assert_equal 1, Tokra::Ipc::Json.parse(" \t\r\n1 \t\r\n")
    assert_rejects "expected value at line 1 column 1", "\v1"
  end

  def test_strings_are_utf8
    string = Tokra::Ipc::Json.parse("\"caf\xC3\xA9\\u00e9\"".b)

    assert_equal ["café\u00e9", Encoding::UTF_8], [string, string.encoding]
    assert_equal "😀", Tokra::Ipc::Json.parse('"\\ud83d\\ude00"')
  end

  def test_rejects_strings_that_are_not_utf8
    assert_rejects "invalid unicode code point at line 1 column 3", "\"\xFF\"".b
    assert_rejects "invalid unicode code point at line 1 column 5", "\"\xED\xA0\x80\"".b
    assert_rejects "invalid unicode code point at line 1 column 4", "\"\xC0\x80\"".b
    assert_rejects "invalid unicode code point at line 1 column 7", "\"\\n\xFF\\n\"".b
    assert_rejects "expected value at line 1 column 1", "\xFF".b
  end

  def test_rejects_unpaired_surrogate_escapes
    assert_rejects "lone leading surrogate in hex escape at line 1 column 7", '"\\udc00"'
    assert_rejects "unexpected end of hex escape at line 1 column 8", '"\\ud800"'
    assert_rejects "unexpected end of hex escape at line 1 column 8", '"\\ud800x"'
    assert_rejects "unexpected end of hex escape at line 1 column 9", '"\\ud800\\n"'
    assert_rejects "lone leading surrogate in hex escape at line 1 column 13", '"\\ud800\\u0041"'
    assert_rejects "EOF while parsing a string at line 1 column 7", '"\\ud800'
    assert_rejects "EOF while parsing a string at line 1 column 8", '"\\ud800\\'
  end

  def test_rejects_bad_escapes_and_control_characters
    assert_rejects "invalid escape at line 1 column 3", '"\\q"'
    assert_rejects "invalid escape at line 1 column 7", '"\\u12g4"'
    assert_rejects "EOF while parsing a string at line 1 column 5", '"\\u12'
    assert_rejects "EOF while parsing a string at line 1 column 2", '"\\'
    assert_rejects "EOF while parsing a string at line 1 column 3", '"ab'
    assert_rejects "control character (\\u0000-\\u001F) found while parsing a string at line 1 column 3",
      "\"a\tb\""
  end

  def test_rejects_what_ruby_json_extends_json_with
    assert_rejects "expected value at line 1 column 1", "/*c*/1"
    assert_rejects "expected value at line 1 column 1", "NaN"
    assert_rejects "expected value at line 1 column 1", "\xEF\xBB\xBF{}".b
    assert_rejects "trailing comma at line 1 column 4", "[1,]"
    assert_rejects "trailing comma at line 1 column 8", '{"a":1,}'
  end

  def test_rejects_malformed_structure_where_serde_json_does
    assert_rejects "EOF while parsing a value at line 1 column 0", ""
    assert_rejects "EOF while parsing a value at line 1 column 1", " "
    assert_rejects "trailing characters at line 1 column 3", "1 2"
    assert_rejects "expected `,` or `]` at line 1 column 4", "[1 2]"
    assert_rejects "EOF while parsing a list at line 1 column 1", "["
    assert_rejects "EOF while parsing a value at line 1 column 3", "[1,"
    assert_rejects "EOF while parsing an object at line 1 column 1", "{"
    assert_rejects "key must be a string at line 1 column 2", "{1:2}"
    assert_rejects "key must be a string at line 1 column 8", '{"a":1,2}'
    assert_rejects "EOF while parsing a value at line 1 column 7", '{"a":1,'
    assert_rejects "expected `:` at line 1 column 6", '{"a" 1}'
    assert_rejects "EOF while parsing an object at line 1 column 4", '{"a"'
    assert_rejects "expected `,` or `}` at line 1 column 8", '{"a":1 "b":2}'
    assert_rejects "EOF while parsing an object at line 1 column 6", '{"a":1'
    assert_rejects "EOF while parsing a value at line 1 column 3", "nul"
    assert_rejects "expected ident at line 1 column 4", "nulx"
    assert_rejects "expected ident at line 1 column 2", "tx"
    assert_rejects "expected ident at line 1 column 3", "fax"
  end

  def test_positions_count_lines_and_bytes
    assert_rejects "expected value at line 3 column 3", "\n [\n  x]"
    assert_rejects "expected value at line 1 column 7", '["é",x]'
  end

  def test_nesting_stops_at_serde_json_recursion_limit
    deep = "#{'[' * 127}#{']' * 127}"

    assert_equal 127, deep_count(Tokra::Ipc::Json.parse(deep))
    assert_rejects "recursion limit exceeded at line 1 column 128", "#{'[' * 128}#{']' * 128}"
    assert_rejects "recursion limit exceeded at line 1 column 132", "{\"a\":#{'[' * 127}"
  end

  private def deep_count(value)
    depth = 0
    while value.is_a?(Array)
      depth += 1
      value = value.first
    end
    depth
  end

  def test_integers_that_fit_64_bits_stay_integers
    assert_equal 18_446_744_073_709_551_615, Tokra::Ipc::Json.parse("18446744073709551615")
    assert_equal [Integer, -9_223_372_036_854_775_808],
      [Tokra::Ipc::Json.parse("-9223372036854775808").class, Tokra::Ipc::Json.parse("-9223372036854775808")]
  end

  def test_negative_zero_and_wider_integers_are_floats
    assert_equal "-0.0", Tokra::Ipc::Json.parse("-0").to_s
    assert_equal "43f0000000000000", float_bits(Tokra::Ipc::Json.parse("18446744073709551616"))
    assert_equal "c3e0000000000000", float_bits(Tokra::Ipc::Json.parse("-9223372036854775809"))
    assert_equal "441ac53a7e04bcd9", float_bits(Tokra::Ipc::Json.parse("123456789012345678901.5"))
    assert_equal "3ff3c0ca428c59fb", float_bits(Tokra::Ipc::Json.parse("1.2345678901234567890123"))
  end

  # Without float_roundtrip serde_json multiplies or divides by a power of
  # ten, which here lands one place off the correctly rounded double
  # Ruby's own parser gives (de.rs:637-675).
  def test_floats_round_as_serde_json_rounds_them
    float = Tokra::Ipc::Json.parse("9563890142136.366848e-9")

    assert_equal "40c2adf1f02d723f", float_bits(float)
    refute_equal "9563890142136.366848e-9".to_f, float
    assert_equal "3fd3333333333333", float_bits(Tokra::Ipc::Json.parse("0.3")), "3 divided by 10"
  end

  def test_number_grammar_and_range
    assert_rejects "invalid number at line 1 column 2", "01"
    assert_rejects "EOF while parsing a value at line 1 column 2", "1."
    assert_rejects "invalid number at line 1 column 3", "1.x"
    assert_rejects "EOF while parsing a value at line 1 column 2", "1e"
    assert_rejects "invalid number at line 1 column 3", "1ex"
    assert_rejects "EOF while parsing a value at line 1 column 3", "1e+"
    assert_rejects "EOF while parsing a value at line 1 column 1", "-"
    assert_rejects "invalid number at line 1 column 2", "-x"
    assert_rejects "number out of range at line 1 column 5", "1e400"
    assert_rejects "number out of range at line 1 column 22", "1.7976931348623159e308"
    assert_rejects "number out of range at line 1 column 12", "1e2147483648"
    assert_rejects "number out of range at line 1 column 12", "1e21474836480"
    assert_equal [0.0, 0.0, 0.0, 100_000.0, 0.0015],
      Tokra::Ipc::Json.parse("[0e2147483648, 1e-2147483648, 1e-400, 1E5, 1.5e-3]")
    assert_equal [0.0, 0.0], Tokra::Ipc::Json.parse("[0e400, 0.0e999]")
    assert_equal [1500.0, 1500.0], Tokra::Ipc::Json.parse("[1.5E3, 1.5e3]")
    assert_equal "-0.0", Tokra::Ipc::Json.parse("-1e-400").to_s
    assert_equal "8000000000000000", float_bits(Tokra::Ipc::Json.parse("-1e-99999999999"))
    assert_equal "40f86a0000000000", float_bits(Tokra::Ipc::Json.parse("1.00000000000000000000001e5")),
      "a fraction too long for 64 bits keeps its exponent"
  end

  def test_duplicate_keys_keep_the_last_value
    assert_equal({ "a" => 2 }, Tokra::Ipc::Json.parse('{"a":1,"a":2}'))
  end

  # serde_json's Map is a BTreeMap without preserve_order, so keys come out
  # in byte order whatever order they arrived in.
  def test_object_keys_are_in_byte_order
    assert_equal ["A", "a", "b", "z", "é"], Tokra::Ipc::Json.parse('{"z":1,"é":2,"b":3,"a":4,"A":5,"b":6}').keys
  end

  # With raw_value, an object whose first key is serde_json's private
  # token reads its string as JSON text (value/de.rs:131-135).
  def test_raw_value_token_as_first_key_reads_the_string_as_json
    token = Tokra::Ipc::Json::RAW_VALUE_TOKEN

    assert_equal [1, 2], Tokra::Ipc::Json.parse("{\"#{token}\":\"[1,2]\"}")
    assert_equal({ "a" => 1, token => "x" }, Tokra::Ipc::Json.parse("{\"a\":1,\"#{token}\":\"x\"}"))
    assert_rejects "EOF while parsing a value at line 1 column 3", "{\"#{token}\":\"[1,\"}"
    assert_rejects "trailing comma at line 1 column 38", "{\"#{token}\":\"1\",\"b\":2}"
    assert_rejects "trailing characters at line 1 column 39", "{\"#{token}\":\"1\" x}"
    assert_rejects "trailing characters at line 1 column 3", "{\"#{token}\":\"1 2\"}"
    assert_rejects "EOF while parsing an object at line 1 column 37", "{\"#{token}\":\"1\""
    assert_rejects "EOF while parsing a value at line 1 column 34", "{\"#{token}\":"
    assert_rejects "expected value at line 1 column 35", "{\"#{token}\":x}"
  end

  def test_raw_value_token_rejects_values_that_are_not_strings
    token = Tokra::Ipc::Json::RAW_VALUE_TOKEN

    assert_rejects "invalid type: floating point `1.5`, expected raw value at line 1 column 37",
      "{\"#{token}\":1.5}"
    assert_rejects "invalid type: integer `-1`, expected raw value at line 1 column 36", "{\"#{token}\":-1}"
    assert_rejects "invalid type: null, expected raw value at line 1 column 38", "{\"#{token}\":null}"
    assert_rejects "invalid type: boolean `true`, expected raw value at line 1 column 38", "{\"#{token}\":true}"
    assert_rejects "invalid type: boolean `false`, expected raw value at line 1 column 39", "{\"#{token}\":false}"
    assert_rejects "invalid type: sequence, expected raw value at line 1 column 34", "{\"#{token}\":[1]}"
    assert_rejects "invalid type: map, expected raw value at line 1 column 34", "{\"#{token}\":{}}"
    assert_rejects "expected ident at line 1 column 38", "{\"#{token}\":tru}"
  end
end
