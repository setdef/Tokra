# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Ipc::FormatCallback.
#
# Output strings are byte-compared against the scripts Tauri's
# format_callback.rs produces.
class TestFormatCallback < Minitest::Test
  def test_formats_string_value_as_json_literal
    assert_equal 'window.__TAURI_INTERNALS__.runCallback(42, "pong")',
      Tokra::Ipc::FormatCallback.format(42, "pong")
  end

  def test_formats_nil_as_null
    assert_equal "window.__TAURI_INTERNALS__.runCallback(7, null)",
      Tokra::Ipc::FormatCallback.format(7, nil)
  end

  def test_formats_integer_value
    assert_equal "window.__TAURI_INTERNALS__.runCallback(1, 12345)",
      Tokra::Ipc::FormatCallback.format(1, 12_345)
  end

  def test_formats_small_object_as_literal
    assert_equal 'window.__TAURI_INTERNALS__.runCallback(9, {"ok":true})',
      Tokra::Ipc::FormatCallback.format(9, { "ok" => true })
  end

  def test_wraps_large_object_in_json_parse
    value = { "data" => "x" * Tokra::Ipc::FormatCallback::MIN_JSON_PARSE_LEN }
    script = Tokra::Ipc::FormatCallback.format(3, value)

    assert script.start_with?("window.__TAURI_INTERNALS__.runCallback(3, JSON.parse('"),
      "large objects should render as JSON.parse for faster engine parsing"
    assert script.end_with?("'))")
  end

  def test_large_array_also_wraps_in_json_parse
    value = Array.new(Tokra::Ipc::FormatCallback::MIN_JSON_PARSE_LEN) { 7 }
    script = Tokra::Ipc::FormatCallback.format(3, value)

    assert_includes script, "JSON.parse('["
  end

  def test_large_string_stays_a_literal
    # Only objects and arrays benefit from JSON.parse (format_callback.rs)
    value = "x" * (Tokra::Ipc::FormatCallback::MIN_JSON_PARSE_LEN + 1)
    script = Tokra::Ipc::FormatCallback.format(3, value)

    refute_includes script, "JSON.parse"
  end

  def test_json_parse_escapes_single_quotes_and_backslashes
    value = { "text" => "it's a backslash: \\", "pad" => "x" * Tokra::Ipc::FormatCallback::MIN_JSON_PARSE_LEN }
    script = Tokra::Ipc::FormatCallback.format(5, value)

    assert_includes script, "it\\'s a backslash: \\\\\\\\",
      "the JSON escape of backslash must itself be escaped for the single-quoted literal"
    refute_match(/[^\\]'s/, script, "no unescaped single quote may terminate the literal early")
  end

  def test_format_raw_takes_a_pre_serialized_json_string
    assert_equal 'window.__TAURI_INTERNALS__.runCallback(11, {"rid":4})',
      Tokra::Ipc::FormatCallback.format_raw(11, '{"rid":4}')
  end
end
