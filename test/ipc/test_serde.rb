# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# serde's visitors as serde_json's Value drives them, each message read
# from serde 1.0.228, serde_core 1.0.228, serde_derive 1.0.228, and
# serde_json 1.0.145.
class TestIpcSerde < Minitest::Test
  S = Tokra::Ipc::Serde
  KINDS = %w[Menu MenuItem Predefined].freeze

  # --- known_variant: serde_core de/mod.rs:252-265, OneOf :2333-2355 ---

  def test_known_variant_answers_a_known_name
    assert_equal "Menu", S.known_variant("Menu", KINDS)
  end

  def test_known_variant_lists_the_variants_as_one_of_words_them
    assert_mismatch("unknown variant `x`, expected `A`") { S.known_variant("x", %w[A]) }
    assert_mismatch("unknown variant `x`, expected `A` or `B`") { S.known_variant("x", %w[A B]) }
    assert_mismatch("unknown variant `x`, expected one of `A`, `B`, `C`") { S.known_variant("x", %w[A B C]) }
    assert_mismatch("unknown variant `x`, there are no variants") { S.known_variant("x", []) }
  end

  # --- unit_variant and enum_variant: serde_json value/de.rs:234-265,
  # 328-347, 556-574 ---

  def test_unit_variant_reads_a_string_or_a_map_of_the_variant_to_null
    assert_equal "Menu", S.unit_variant("Menu", KINDS)
    assert_equal "Predefined", S.unit_variant({ "Predefined" => nil }, KINDS)
  end

  def test_unit_variant_rejects_in_serdes_words
    assert_mismatch("invalid type: integer `1`, expected unit") { S.unit_variant({ "Menu" => 1 }, KINDS) }
    assert_mismatch("invalid value: map, expected map with a single key") { S.unit_variant({}, KINDS) }
    assert_mismatch("invalid value: map, expected map with a single key") do
      S.unit_variant({ "Menu" => nil, "MenuItem" => nil }, KINDS)
    end
    assert_mismatch("invalid type: integer `1`, expected string or map") { S.unit_variant(1, KINDS) }
    assert_mismatch("invalid type: sequence, expected string or map") { S.unit_variant(["Menu"], KINDS) }
    assert_mismatch("unknown variant `Tray`, expected one of `Menu`, `MenuItem`, `Predefined`") do
      S.unit_variant("Tray", KINDS)
    end
  end

  # The variant's name is read before its content.
  def test_unit_variant_names_an_unknown_variant_before_its_content
    assert_mismatch("unknown variant `Tray`, expected one of `Menu`, `MenuItem`, `Predefined`") do
      S.unit_variant({ "Tray" => 1 }, KINDS)
    end
  end

  def test_enum_variant_answers_a_newtype_variants_content
    assert_equal ["Logical", { "x" => 1 }], S.enum_variant({ "Logical" => { "x" => 1 } }, %w[Physical Logical], newtype: %w[Logical])
    assert_equal ["Logical", nil], S.enum_variant({ "Logical" => nil }, %w[Physical Logical], newtype: %w[Logical])
    assert_equal ["Physical", nil], S.enum_variant("Physical", %w[Physical Logical], newtype: %w[Logical])
  end

  def test_enum_variant_rejects_a_bare_newtype_variant_and_a_unit_variants_content
    assert_mismatch("invalid type: unit variant, expected newtype variant") do
      S.enum_variant("Logical", %w[Physical Logical], newtype: %w[Logical])
    end
    assert_mismatch("invalid type: boolean `true`, expected unit") do
      S.enum_variant({ "Physical" => true }, %w[Physical Logical], newtype: %w[Logical])
    end
    assert_mismatch("unknown variant `Other`, expected `Physical` or `Logical`") do
      S.enum_variant("Other", %w[Physical Logical], newtype: %w[Logical])
    end
  end

  # --- internally_tagged: serde private/de.rs:816-886, serde_derive
  # de/enum_internally.rs:46-56 ---

  def test_internally_tagged_reads_the_tag_from_a_map_and_answers_the_rest
    assert_equal ["Menu", { "label" => "a" }], S.internally_tagged({ "kind" => "Menu", "label" => "a" }, "kind", "Thing", KINDS)
  end

  def test_internally_tagged_reads_the_tag_from_a_sequences_first_element
    assert_equal ["Menu", ["a", 1]], S.internally_tagged(["Menu", "a", 1], "kind", "Thing", KINDS)
    assert_equal ["Menu", []], S.internally_tagged(["Menu"], "kind", "Thing", KINDS)
  end

  def test_internally_tagged_rejects_in_serdes_words
    assert_mismatch("missing field `kind`") { S.internally_tagged({ "label" => "a" }, "kind", "Thing", KINDS) }
    assert_mismatch("missing field `kind`") { S.internally_tagged([], "kind", "Thing", KINDS) }
    assert_mismatch("invalid type: string \"a\", expected internally tagged enum Thing") do
      S.internally_tagged("a", "kind", "Thing", KINDS)
    end
    assert_mismatch("invalid type: integer `1`, expected variant identifier") do
      S.internally_tagged({ "kind" => 1 }, "kind", "Thing", KINDS)
    end
    assert_mismatch("invalid type: integer `1`, expected variant identifier") do
      S.internally_tagged([1], "kind", "Thing", KINDS)
    end
    assert_mismatch("unknown variant `Tray`, expected one of `Menu`, `MenuItem`, `Predefined`") do
      S.internally_tagged(["Tray"], "kind", "Thing", KINDS)
    end
  end

  # --- struct_fields: serde_derive de.rs:450-505 (visit_seq),
  # de/struct_.rs (visit_map), serde_json value/de.rs:731-746 ---

  def test_struct_fields_reads_a_map_and_a_sequence
    expected = { "a" => "A", "b" => "B" }

    assert_equal expected, S.struct_fields({ "b" => "b", "a" => "a" }, "Pair", %w[a b]) { |_, raw| raw.upcase }
    assert_equal expected, S.struct_fields(%w[a b], "Pair", %w[a b]) { |_, raw| raw.upcase }
  end

  def test_struct_fields_reads_a_map_in_its_key_order
    read = []
    S.struct_fields({ "b" => 1, "a" => 2 }, "Pair", %w[a b]) { |field, _| read << field }

    assert_equal %w[b a], read
  end

  def test_struct_fields_reads_every_present_field_before_naming_a_missing_one
    assert_mismatch("bad b") { S.struct_fields({ "b" => 1 }, "Pair", %w[a b]) { |field, _| raise mismatch("bad #{field}") } }
    assert_mismatch("missing field `a`") { S.struct_fields({ "b" => 1, "c" => 2 }, "Trio", %w[a b c]) { |_, raw| raw } }
    assert_mismatch("missing field `a`") { S.struct_fields({}, "Pair", %w[a b]) { |_, raw| raw } }
  end

  def test_struct_fields_ignores_an_unknown_key_unless_told_to_deny_it
    assert_equal({ "a" => 1 }, S.struct_fields({ "a" => 1, "z" => 2 }, "One", %w[a]) { |_, raw| raw })
    assert_mismatch("unknown field `z`, expected `a`") do
      S.struct_fields({ "a" => 1, "z" => 2 }, "One", %w[a], deny_unknown: true) { |_, raw| raw }
    end
    assert_mismatch("unknown field `z`, expected `a` or `b`") do
      S.struct_fields({ "z" => 2 }, "Pair", %w[a b], deny_unknown: true) { |_, raw| raw }
    end
    assert_mismatch("unknown field `z`, there are no fields") do
      S.struct_fields({ "z" => 2 }, "None", [], deny_unknown: true) { |_, raw| raw }
    end
  end

  # An unknown key fails when it is reached, before a later bad field.
  def test_struct_fields_denies_an_unknown_key_in_key_order
    assert_mismatch("unknown field `b`, expected `a` or `c`") do
      S.struct_fields({ "b" => 1, "c" => 2 }, "Pair", %w[a c], deny_unknown: true) { |_, _| raise mismatch("read") }
    end
  end

  # An Option field is +nil+ when a map lacks it or holds null, and the
  # block never sees the null; a sequence must still reach it.
  def test_struct_fields_reads_an_optional_field_as_an_option
    read = S.struct_fields({ "b" => nil }, "Pair", %w[a b], optional: %w[a b]) { |_, raw| raw.upcase }

    assert_equal({ "a" => nil, "b" => nil }, read)
    assert_equal({ "a" => "A", "b" => nil }, S.struct_fields(["a", nil], "Pair", %w[a b], optional: %w[b]) { |_, raw| raw.upcase })
    assert_mismatch("invalid length 1, expected struct Pair with 2 elements") do
      S.struct_fields(["a"], "Pair", %w[a b], optional: %w[a b]) { |_, raw| raw }
    end
  end

  def test_struct_fields_reads_a_sequence_element_by_element
    assert_mismatch("bad a") { S.struct_fields([1], "Pair", %w[a b]) { |field, _| raise mismatch("bad #{field}") } }
    assert_mismatch("invalid length 1, expected struct Pair with 2 elements") { S.struct_fields([1], "Pair", %w[a b]) { |_, raw| raw } }
    assert_mismatch("invalid length 0, expected struct One with 1 element") { S.struct_fields([], "One", %w[a]) { |_, raw| raw } }
  end

  def test_struct_fields_rejects_elements_left_over_after_reading_them
    assert_mismatch("invalid length 3, expected fewer elements in array") do
      S.struct_fields([1, 2, 3], "Pair", %w[a b]) { |_, raw| raw }
    end
    assert_mismatch("bad b") { S.struct_fields([1, 2, 3], "Pair", %w[a b]) { |field, raw| (raw == 2) ? raise(mismatch("bad #{field}")) : raw } }
  end

  def test_struct_fields_rejects_anything_else_as_the_struct
    assert_mismatch("invalid type: integer `5`, expected struct Pair") { S.struct_fields(5, "Pair", %w[a b]) { |_, raw| raw } }
    assert_mismatch("invalid type: null, expected struct Pair") { S.struct_fields(nil, "Pair", %w[a b]) { |_, raw| raw } }
  end

  # --- tuple: serde_core de/impls.rs:1411-1423, serde_json
  # value/de.rs:731-746, 970-985 ---

  def test_tuple_reads_each_element_with_its_index
    assert_equal ["0a", "1b"], S.tuple(%w[a b], 2) { |index, raw| "#{index}#{raw}" }
  end

  def test_tuple_reads_element_by_element_then_rejects_elements_left_over
    assert_mismatch("bad 0") { S.tuple([1, 2, 3], 2) { |index, _| raise mismatch("bad #{index}") } }
    assert_mismatch("invalid length 1, expected a tuple of size 2") { S.tuple([1], 2) { |_, raw| raw } }
    assert_mismatch("invalid length 3, expected fewer elements in array") { S.tuple([1, 2, 3], 2) { |_, raw| raw } }
    assert_mismatch("invalid type: map, expected a tuple of size 2") { S.tuple({}, 2) { |_, raw| raw } }
  end

  # --- scalars: serde_core de/impls.rs, the primitive and string
  # visitors ---

  def test_string_and_borrowed_str
    assert_equal "a", S.string("a")
    assert_equal "a", S.borrowed_str("a")
    assert_mismatch("invalid type: integer `1`, expected a string") { S.string(1) }
    assert_mismatch("invalid type: null, expected a borrowed string") { S.borrowed_str(nil) }
  end

  def test_boolean
    assert S.boolean(true)
    refute S.boolean(false)
    assert_mismatch("invalid type: string \"true\", expected a boolean") { S.boolean("true") }
    assert_mismatch("invalid type: null, expected a boolean") { S.boolean(nil) }
  end

  def test_f64_takes_an_integer_or_a_float
    assert_equal 2.0, S.f64(2)
    assert_kind_of Float, S.f64(2)
    assert_equal 1.5, S.f64(1.5)
    assert_mismatch("invalid type: string \"1\", expected f64") { S.f64("1") }
    assert_mismatch("invalid type: boolean `true`, expected f64") { S.f64(true) }
  end

  private def mismatch(message)
    Tokra::Ipc::CommandItem::Mismatch.new(message)
  end

  private def assert_mismatch(message, &)
    error = assert_raises(Tokra::Ipc::CommandItem::Mismatch, &)
    assert_equal message, error.message
  end
end
