# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Path::BaseDirectory has Tauri's 23 desktop variants, numbered as
# @tauri-apps/api/path numbers them, with the variables
# PathResolver#parse reads (path/mod.rs:86-247).
class TestBaseDirectory < Minitest::Test
  B = Tokra::Path::BaseDirectory
  PATH_TS = File.expand_path("../../vendor/tauri/packages/api/src/path.ts", __dir__)
  MOD_RS = File.expand_path("../../vendor/tauri/crates/tauri/src/path/mod.rs", __dir__)

  # The page sends the numbers path.ts declares, so they are the answer
  # key for the values.
  def test_the_variants_are_the_pages_numbers
    declared = File.read(PATH_TS)[/enum BaseDirectory \{(.*?)\n\}/m, 1].scan(/(\w+) = (\d+)/)
      .to_h { |name, value| [name, Integer(value)] }

    assert_equal 23, declared.size
    assert_equal declared, B.variants.to_h { |directory| [directory.name, directory.value] }
    declared.each_key { |name| assert_same B.const_get(name), B.variants.find { |directory| directory.name == name } }
  end

  def test_each_variable_is_tauris
    variables = File.read(MOD_RS)[/pub fn variable.*?\n  \}/m].scan(/Self::(\w+) => "(\$\w+)"/).to_h

    assert_equal 23, variables.size
    variables.each do |name, variable|
      assert_equal variable, B.const_get(name).variable, name
      assert_same B.const_get(name), B.from_variable(variable), variable
    end
  end

  def test_an_unknown_variable_is_none
    assert_nil B.from_variable("$NOPE")
    assert_nil B.from_variable("$home")
    assert_nil B.from_variable("HOME")
  end

  def test_a_number_reads_as_its_variant
    assert_same B::AppData, B.deserialize(14)
    assert_same B::Template, B.deserialize(23)
  end

  # serde reads a u16 first (serde de/impls.rs), then serde_repr 0.1.19
  # matches it, listing every desktop discriminant.
  def test_a_value_that_is_no_variant_fails_in_serdes_words
    one_of = "expected one of: #{(1..23).to_a.join(', ')}"
    {
      0 => "invalid value: 0, #{one_of}",
      24 => "invalid value: 24, #{one_of}",
      65_535 => "invalid value: 65535, #{one_of}",
      65_536 => "invalid value: integer `65536`, expected u16",
      -1 => "invalid value: integer `-1`, expected u16",
      1.5 => "invalid type: floating point `1.5`, expected u16",
      "1" => "invalid type: string \"1\", expected u16",
      nil => "invalid type: null, expected u16",
    }.each do |value, message|
      error = assert_raises(Tokra::Ipc::CommandItem::Mismatch, value.inspect) { B.deserialize(value) }
      assert_equal message, error.message
    end
  end

  def test_no_other_variant_can_be_built
    assert_raises(NoMethodError) { B.new(name: "Elsewhere", value: 99) }
  end
end
