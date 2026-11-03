# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# The forms Tauri's config types take, read by Ipc::Serde and checked
# against what serde_json::from_value made of the same values in Tauri's
# own types (test/fixtures/config/from_value, written by rake
# config:fixtures from tauri-utils at vendor/tauri 9f0306fbc).
#
# Each reader below mirrors one tauri-utils type, field for field, from
# crates/tauri-utils/src/config.rs; only the readers' Serde calls are
# under test.
class TestIpcSerdeConfigForms < Minitest::Test
  S = Tokra::Ipc::Serde
  Mismatch = Tokra::Ipc::CommandItem::Mismatch
  FIXTURES = File.expand_path("../fixtures/config/from_value", __dir__)

  # config.rs:2802-2840.
  TRAY_FIELDS = %w[id iconPath iconAsTemplate menuOnLeftClick showMenuOnLeftClick title tooltip].freeze
  TRAY_ALIASES = {
    "iconPath" => ["icon-path"],
    "iconAsTemplate" => ["icon-as-template"],
    "menuOnLeftClick" => ["menu-on-left-click"],
    "showMenuOnLeftClick" => ["show-menu-on-left-click"],
  }.freeze
  TRAY_DEFAULTS = { "iconAsTemplate" => false, "menuOnLeftClick" => true, "showMenuOnLeftClick" => true }.freeze
  TRAY_FLAGS = %w[iconAsTemplate menuOnLeftClick showMenuOnLeftClick].freeze

  # config.rs:2687-2766.
  APP_FIELDS = %w[windows security trayIcon macOSPrivateApi withGlobalTauri enableGTKAppId].freeze
  APP_ALIASES = {
    "trayIcon" => ["tray-icon"],
    "macOSPrivateApi" => ["macos-private-api"],
    "withGlobalTauri" => ["with-global-tauri"],
    "enableGTKAppId" => ["enable-gtk-app-id"],
  }.freeze
  APP_DEFAULTS = {
    "windows" => [], "security" => {}, "macOSPrivateApi" => false, "withGlobalTauri" => false, "enableGTKAppId" => false
  }.freeze

  # The cases and what Tauri answered, by name.
  def self.answers
    @answers ||= begin
      cases = File.readlines(File.join(FIXTURES, "cases.jsonl"), chomp: true).reject(&:empty?)
        .to_h { |line| (row = Tokra::Ipc::Json.parse(line)).then { [row.fetch("name"), row] } }
      File.readlines(File.join(FIXTURES, "expected.jsonl"), chomp: true).reject(&:empty?).to_h do |line|
        answer = Tokra::Ipc::Json.parse(line)
        [answer.fetch("name"), cases.fetch(answer.fetch("name")).merge(answer)]
      end
    end
  end

  def test_every_case_has_its_answer
    cases = File.readlines(File.join(FIXTURES, "cases.jsonl"), chomp: true).reject(&:empty?)
    assert_equal cases.size, self.class.answers.size
    self.class.answers.each_value { |answer| assert_equal "json", answer.fetch("build") }
  end

  # --- aliases: serde_derive de/identifier.rs:196-215 ---

  def test_an_alias_reads_its_field
    assert_answer("tray_alias") { |value| tray(value) }
    assert_answer("app_aliases") { |value| app(value) }
    assert_answer("asset_protocol_scope_alias") { |value| asset_protocol(value) }
  end

  # FIELDS holds each field's BTreeSet of names, the name among them, in
  # byte order (de/struct_.rs:55-131; internals/name.rs:71-75).
  def test_an_unknown_field_lists_each_fields_names_sorted_within_the_field
    assert_answer("tray_unknown_field") { |value| tray(value) }
    assert_answer("app_unknown_field") { |value| app(value) }
  end

  def test_a_field_named_twice_by_its_aliases_is_a_duplicate
    assert_answer("tray_alias_and_name_both") { |value| tray(value) }
    # The name sorts before the alias here, and the error still names the
    # field, not the key that repeated it.
    assert_answer("app_duplicate_canonical_first") { |value| app(value) }
  end

  # --- defaults: de/struct_.rs:330-345 (map), de.rs:451-505 (sequence) ---

  def test_a_default_fills_a_field_a_map_leaves_out
    assert_answer("tray_defaults_from_a_map") { |value| tray(value) }
    assert_answer("app_defaults_from_a_map") { |value| app(value) }
  end

  def test_a_default_fills_a_field_a_short_array_does_not_reach
    assert_answer("asset_protocol_empty_array") { |value| asset_protocol(value) }
    assert_answer("asset_protocol_short_array") { |value| asset_protocol(value) }
  end

  # An Option with no default is filled from a map, not from an array.
  def test_a_short_array_stops_at_the_first_field_without_a_default
    assert_answer("tray_short_array") { |value| tray(value) }
    assert_answer("app_short_array") { |value| app(value) }
  end

  def test_a_full_array_reads_every_field_and_a_long_one_is_refused
    assert_answer("tray_full_array") { |value| tray(value) }
    assert_answer("tray_long_array") { |value| tray(value) }
  end

  def test_a_missing_field_without_a_default_is_refused
    assert_answer("tray_missing_field") { |value| tray(value) }
    assert_answer("prevent_overflow_margin_missing_field") { |value| margin(value) }
  end

  # --- untagged enums: de/enum_untagged.rs ---

  def test_an_untagged_enum_reads_its_first_variant_that_matches
    assert_answer("fs_scope_first_variant") { |value| fs_scope(value) }
    assert_answer("fs_scope_second_variant") { |value| fs_scope(value) }
    assert_answer("prevent_overflow_first_variant") { |value| prevent_overflow(value) }
    assert_answer("prevent_overflow_second_variant") { |value| prevent_overflow(value) }
    assert_answer("runner_second_variant") { |value| runner(value) }
  end

  # A newtype variant over a struct reads an array; a struct variant does
  # not, having no visit_seq (de/struct_.rs:70-73).
  def test_an_untagged_struct_variant_reads_only_a_map
    assert_answer("prevent_overflow_second_variant_from_an_array") { |value| prevent_overflow(value) }
    assert_answer("fs_scope_struct_variant_refuses_an_array") { |value| fs_scope(value) }
    assert_answer("runner_struct_variant_refuses_an_array") { |value| runner(value) }
  end

  def test_an_untagged_enum_names_itself_when_no_variant_matches
    assert_answer("fs_scope_no_variant") { |value| fs_scope(value) }
    assert_answer("prevent_overflow_no_variant") { |value| prevent_overflow(value) }
  end

  # No untagged enum in Tauri's config has two variants that read the
  # same value, so the order shows only in a made-up one: serde tries the
  # variants in declaration order and keeps the first that reads
  # (de/enum_untagged.rs:28-58).
  def test_an_untagged_enum_tries_its_variants_in_order
    readers = [-> (_value) { raise Mismatch, "no" }, -> (_value) { "second" }, -> (_value) { "third" }]
    assert_equal "second", S.untagged("x", "Made", readers)
  end

  def test_an_untagged_enum_lets_any_other_error_through
    error = assert_raises(ArgumentError) { S.untagged(1, "Broken", [-> (_value) { raise ArgumentError, "a bug" }]) }
    assert_equal "a bug", error.message
  end

  # --- adjacently tagged enums: de/enum_adjacently.rs ---

  def test_an_adjacently_tagged_enum_reads_each_variant
    assert_answer("pattern_unit_variant") { |value| pattern(value) }
    assert_answer("pattern_struct_variant") { |value| pattern(value) }
    assert_answer("pattern_unit_variant_with_null_content") { |value| pattern(value) }
  end

  # The tag reads as serde_json's deserialize_enum reads a unit variant.
  def test_an_adjacently_tagged_enums_tag_reads_as_a_unit_variant
    assert_answer("pattern_tag_as_a_map") { |value| pattern(value) }
    assert_answer("pattern_unknown_variant") { |value| pattern(value) }
    assert_answer("pattern_tag_of_the_wrong_type") { |value| pattern(value) }
  end

  def test_an_adjacently_tagged_enum_needs_its_tag_and_a_non_unit_variant_its_content
    assert_answer("pattern_missing_tag") { |value| pattern(value) }
    assert_answer("pattern_content_without_tag") { |value| pattern(value) }
    assert_answer("pattern_missing_content") { |value| pattern(value) }
  end

  # "options" sorts before "use", so the content is buffered and read
  # once the tag is known.
  def test_an_adjacently_tagged_enums_content_is_read_by_its_variant
    assert_answer("pattern_unit_variant_with_content") { |value| pattern(value) }
    assert_answer("pattern_unit_variant_with_boolean_content") { |value| pattern(value) }
    # serde_json words a float through ryu whichever deserializer failed
    # (serde_json error.rs:440-474).
    assert_answer("pattern_unit_variant_with_float_content") { |value| pattern(value) }
    assert_answer("pattern_struct_variant_refuses_an_array") { |value| pattern(value) }
  end

  def test_an_adjacently_tagged_enum_without_deny_unknown_fields_steps_over_other_keys
    assert_answer("pattern_other_keys_ignored") { |value| pattern(value) }
  end

  def test_an_adjacently_tagged_enum_with_deny_unknown_fields_refuses_other_keys
    error = assert_raises(Mismatch) do
      S.adjacently_tagged({ "a" => 1, "use" => "brownfield" }, "use", "options", "PatternKind", %w[brownfield],
        unit: %w[brownfield], deny_unknown: true) { |_variant, raw| raw }
    end
    assert_equal 'invalid value: string "a", expected "use" or "options"', error.message
  end

  # serde visits the keys left after the tag and the content
  # (de/enum_adjacently.rs:152-165), so one sorted after both is refused
  # too, once the content has been read.
  def test_an_adjacently_tagged_enum_with_deny_unknown_fields_refuses_a_key_after_both
    read = []
    error = assert_raises(Mismatch) do
      S.adjacently_tagged({ "options" => nil, "use" => "brownfield", "zzz" => 1 }, "use", "options", "PatternKind",
        %w[brownfield], deny_unknown: true) { |variant, raw| read << [variant, raw] }
    end
    assert_equal 'invalid value: string "zzz", expected "use" or "options"', error.message
    assert_equal [["brownfield", nil]], read
  end

  def test_an_adjacently_tagged_enum_reads_a_tag_and_content_array
    assert_answer("pattern_from_an_array") { |value| pattern(value) }
    assert_answer("pattern_unit_variant_from_a_short_array") { |value| pattern(value) }
    assert_answer("pattern_from_an_empty_array") { |value| pattern(value) }
    assert_answer("pattern_from_a_long_array") { |value| pattern(value) }
    assert_answer("pattern_tag_in_an_array_as_a_map") { |value| pattern(value) }
  end

  def test_an_adjacently_tagged_enum_is_a_map_or_an_array
    assert_answer("pattern_not_a_map") { |value| pattern(value) }
  end

  # Reads the case +name+'s value with the block, and checks the result
  # or the error against Tauri's answer.
  private def assert_answer(name, &read)
    answer = self.class.answers.fetch(name)
    if answer.key?("error")
      error = assert_raises(Mismatch, name) { read.call(answer.fetch("value")) }
      assert_equal answer.fetch("error"), error.message, name
    else
      result = read.call(answer.fetch("value"))
      expected = answer.fetch("ok")
      result = answer.fetch("probes").to_h { |probe| [probe, dig(result, probe)] } if answer.key?("probes")
      assert_equal expected, result, name
    end
  end

  private def dig(value, pointer)
    pointer.split("/").drop(1).reduce(value) { |at, key| at.is_a?(Array) ? at[Integer(key)] : at[key] }
  end

  # The readers, each one type of config.rs. TrayIconConfig and
  # RunnerConfig drop nil fields, as skip_serializing_none writes them back.

  private def tray(value)
    S.struct_fields(value, "TrayIconConfig", TRAY_FIELDS, optional: %w[id title tooltip], aliases: TRAY_ALIASES,
      defaults: TRAY_DEFAULTS, deny_unknown: true) do |field, raw|
      TRAY_FLAGS.include?(field) ? S.boolean(raw) : S.string(raw)
    end.compact
  end

  private def app(value)
    S.struct_fields(value, "AppConfig", APP_FIELDS, optional: %w[trayIcon], aliases: APP_ALIASES, defaults: APP_DEFAULTS,
      deny_unknown: true) do |field, raw|
      case field
      when "windows" then sequence(raw) { flunk "no case reads a window" }
      when "security" then flunk "no case reads security"
      when "trayIcon" then tray(raw)
      else S.boolean(raw)
      end
    end
  end

  # config.rs:2272-2283.
  private def asset_protocol(value)
    S.struct_fields(value, "AssetProtocolConfig", %w[scope enable], defaults: { "scope" => [], "enable" => false },
      deny_unknown: true) do |field, raw|
      (field == "scope") ? fs_scope(raw) : S.boolean(raw)
    end
  end

  # config.rs:2217-2274.
  private def fs_scope(value)
    S.untagged(value, "FsScope", [
      -> (raw) { paths(raw) },
      lambda do |raw|
        S.untagged_struct_variant(raw, "FsScope::Scope", %w[allow deny requireLiteralLeadingDot],
          optional: %w[requireLiteralLeadingDot],
          aliases: { "requireLiteralLeadingDot" => ["require-literal-leading-dot"] },
          defaults: { "allow" => [], "deny" => [] }) do |field, scope|
          (field == "requireLiteralLeadingDot") ? S.boolean(scope) : paths(scope)
        end
      end,
    ])
  end

  # config.rs:1590-1618.
  private def prevent_overflow(value)
    S.untagged(value, "PreventOverflowConfig", [-> (raw) { S.boolean(raw) }, -> (raw) { margin(raw) }])
  end

  private def margin(value)
    S.struct_fields(value, "PreventOverflowMargin", %w[width height], deny_unknown: true) do |_field, raw|
      Tokra::Ipc::CommandItem.integer(raw, "u32")
    end
  end

  # config.rs:2997-3016.
  private def runner(value)
    S.untagged(value, "RunnerConfig", [
      -> (raw) { S.string(raw) },
      lambda do |raw|
        S.untagged_struct_variant(raw, "RunnerConfig::Object", %w[cmd cwd args], optional: %w[cwd args]) do |field, item|
          (field == "args") ? sequence(item) { |arg| S.string(arg) } : S.string(item)
        end.compact
      end,
    ])
  end

  # config.rs:2671-2685.
  private def pattern(value)
    variant, options = S.adjacently_tagged(value, "use", "options", "PatternKind", %w[brownfield isolation],
      unit: %w[brownfield]) do |name, raw|
      if name == "brownfield"
        S.untagged_unit(raw, "PatternKind::Brownfield")
      else
        S.untagged_struct_variant(raw, "PatternKind::Isolation", %w[dir]) { |_field, dir| S.string(dir) }
      end
    end
    options.nil? ? { "use" => variant } : { "use" => variant, "options" => options }
  end

  private def paths(value)
    sequence(value) { |path| S.string(path) }
  end

  private def sequence(value, &)
    raise Mismatch.invalid_type(value, "a sequence") unless value.is_a?(Array)

    value.map(&)
  end
end
