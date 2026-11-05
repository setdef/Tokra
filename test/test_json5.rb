# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/config_fixtures"

# Tokra::Json5 held up against json5 0.4.1 itself. Each case in
# test/fixtures/config/json5/cases.jsonl is a JSON5 text, and
# expected.jsonl holds what json5::from_str::<serde_json::Value> answered
# for it in the config fixture generator (rake config:fixtures): the value,
# or the error's Display and location. The cases carry json5's own tests
# (tests/de.rs, tests/adapted_from_js_reference.rs, tests/examples.rs),
# read into a Value as Tauri reads a config, and cases of Tokra's for the
# deserializer's errors and pest's syntax errors.
class TestJson5 < Minitest::Test
  ConfigFixtures.json5.each do |name, row|
    define_method(:"test_#{name}") do
      if row.key?("ok")
        assert_same_value row.fetch("ok"), Tokra::Json5.from_str(row.fetch("text")), name
      else
        error = assert_raises(Tokra::Json5::Error, name) { Tokra::Json5.from_str(row.fetch("text")) }
        assert_equal row.fetch("error"), error.message, name
        line, column = row.fetch("location")
        assert_equal Tokra::Json5::Location.new(line:, column:), error.location, name
      end
    end
  end

  def test_every_case_has_an_answer
    cases = File.readlines(File.join(ConfigFixtures::ROOT, "json5", "cases.jsonl"), chomp: true).reject(&:empty?)
    assert_equal cases.size, ConfigFixtures.json5.size
  end

  # json5 has no nesting limit, and Tokra's parser keeps its own stack, so
  # nesting far past what Ruby's stack holds reads (plan 054, decision 5).
  def test_nesting_does_not_reach_rubys_stack
    depth = 100_000
    value = Tokra::Json5.from_str(("[" * depth) + ("]" * depth))
    (depth - 1).times { value = value.fetch(0) }
    assert_equal [], value
  end

  def test_an_unclosed_deep_nesting_reports_where_it_ends
    error = assert_raises(Tokra::Json5::Error) { Tokra::Json5.from_str("{a:" * 50_000) }
    assert_equal Tokra::Json5::Location.new(line: 1, column: 150_001), error.location
  end

  # Rust's &str holds only UTF-8, so text invalid in its encoding raises
  # as Tokra::Ipc::Response does, and another valid encoding is converted.
  def test_text_invalid_in_its_encoding_raises
    error = assert_raises(ArgumentError) { Tokra::Json5.from_str("[\"\xFF\"]".dup.force_encoding(Encoding::UTF_8)) }
    assert_equal "invalid byte sequence in UTF-8", error.message
    assert_raises(ArgumentError) { Tokra::Json5.from_str("[1]\xFF".b.force_encoding(Encoding::US_ASCII)) }
  end

  def test_text_in_another_encoding_is_converted
    assert_equal ["é"], Tokra::Json5.from_str("['é']".encode(Encoding::UTF_16LE))
  end

  def test_text_that_is_not_a_string_raises
    assert_raises(TypeError) { Tokra::Json5.from_str(nil) }
  end

  # Ruby's Float() warns when a decimal leaves f64's range; Rust's parse
  # does not, and json5 turns an infinity into its own error. Tokra
  # decides the edges itself, so no warning reaches the app's stderr.
  def test_numbers_at_f64s_edges_read_without_a_warning
    with_warnings do
      assert_silent do
        Tokra::Json5.from_str("[1.7976931348623158e308, 2.4703282292062327e-324, -3e-324, 1e-400]")
        assert_raises(Tokra::Json5::Error) { Tokra::Json5.from_str("1.7976931348623159e308") }
        assert_raises(Tokra::Json5::Error) { Tokra::Json5.from_str("1e400") }
      end
    end
  end

  # serde_json's map keeps its keys in byte order, and the config's schema
  # reads them in that order (plan 054, decision 4).
  def test_object_keys_are_in_byte_order
    assert_equal %w[B a b é], Tokra::Json5.from_str("{b:1,a:2,B:3,'é':4}").keys
  end

  def test_the_value_is_unfrozen_ruby_data
    value = Tokra::Json5.from_str("{a: [1]}")
    assert_equal({ "a" => [1] }, value)
    refute_predicate value, :frozen?
  end

  private def with_warnings
    verbose = $VERBOSE
    $VERBOSE = true
    yield
  ensure
    $VERBOSE = verbose
  end

  # A json value compared as serde_json compares one, a Float to a Float
  # and an Integer to an Integer, with -0.0 kept apart from 0.0, and an
  # object's keys in their order.
  private def assert_same_value(expected, actual, name)
    return assert_nil(actual, name) if expected.nil?

    assert_equal expected, actual, name
    assert_equal shape(expected), shape(actual), name
  end

  private def shape(value)
    stack = [value]
    shapes = []
    until stack.empty?
      item = stack.pop
      case item
      when Hash
        shapes << [:object, item.keys]
        stack.concat(item.values)
      when Array
        shapes << [:array, item.size]
        stack.concat(item)
      when Float then shapes << [:float, item.to_s]
      else shapes << [item.class, item]
      end
    end
    shapes
  end
end
