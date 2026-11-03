# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../../support/config_fixtures"

# Reading config files, held up against what tauri-utils' config::parse
# and tauri-codegen's get_config answered for the same files on each
# desktop target (test/fixtures/config/cases, the build without Tauri's
# optional formats). Each case is copied into a fresh directory and read
# for all three targets, whatever this machine runs: the files, the
# platform's file merged over the main one, and the schema.
class TestUtilsConfigParse < Minitest::Test
  C = Tokra::Utils::Config
  P = C::Parse
  Target = Tokra::Utils::Platform::Target

  # Cases whose answer is an operating system's own words for reading a
  # directory, which Windows gives differently (plan 054, decision 5).
  OS_WORDS = %w[config_is_a_directory platform_file_is_a_directory version_directory].freeze

  ConfigFixtures.case_names.each do |name|
    define_method(:"test_case_#{name}") do
      skip "Windows words a directory's read error its own way" if OS_WORDS.include?(name) && windows?
      ConfigFixtures.answers(name).each { |answer| assert_case(name, answer) }
    end
  end

  def test_every_case_has_an_answer_for_each_target
    ConfigFixtures.case_names.each do |name|
      assert_equal ConfigFixtures::TARGETS.keys, ConfigFixtures.answers(name).map { |answer| answer.fetch("target") }, name
    end
  end

  # --- merge: json-patch 3.0.1 lib.rs:661-678, RFC 7396 ---

  def test_merge_merges_objects_deletes_nulls_and_replaces_the_rest
    doc = { "a" => { "b" => 1, "c" => 2 }, "list" => [1, 2], "gone" => true }
    patch = { "a" => { "c" => nil, "d" => 3 }, "list" => [3], "gone" => nil, "new" => { "x" => nil, "y" => 1 } }
    assert_equal({ "a" => { "b" => 1, "d" => 3 }, "list" => [3], "new" => { "y" => 1 } }, P.merge(doc, patch))
    assert_equal({ "a" => { "b" => 1, "c" => 2 }, "list" => [1, 2], "gone" => true }, doc)
  end

  def test_merge_replaces_with_anything_but_an_object
    assert_equal [1], P.merge({ "a" => 1 }, [1])
    assert_equal({ "a" => 1 }, P.merge([1], { "a" => 1 }))
  end

  # serde_json's Map is a BTreeMap, so a merged object reads in byte
  # order, as serde reads its keys (plan 054, decision 4).
  def test_merge_keeps_every_object_in_byte_order
    merged = P.merge({ "b" => { "z" => 1 }, "a" => 1 }, { "B" => 2, "b" => { "a" => 2 } })
    assert_equal %w[B a b], merged.keys
    assert_equal %w[a z], merged.fetch("b").keys
  end

  # --- the macro's check: parse.rs:206-225 ---

  def test_the_check_looks_for_the_platform_names_beside_a_platform_file
    ConfigFixtures.with_case("platform_file_at_a_given_path") do |dir|
      path = File.join(dir, "tokra.macos.conf.json")
      assert P.does_supported_file_name_exist(Target::MacOS, path)
      refute P.does_supported_file_name_exist(Target::Linux, path)
      refute P.does_supported_file_name_exist(Target::Windows, path)
    end
  end

  def test_the_check_finds_no_disabled_format
    ConfigFixtures.with_case("json5_only") do |dir|
      refute P.does_supported_file_name_exist(Target.current, File.join(dir, "tokra.conf.json"))
    end
  end

  # --- the errors ---

  def test_each_error_is_a_config_error_with_its_readers
    error = P::ConfigError::Io.new("/app/tokra.conf.json", "entity not found")
    assert_kind_of Tokra::Error, error
    assert_equal ["/app/tokra.conf.json", "entity not found"], [error.path, error.error]
    disabled = P::ConfigError::DisabledFormat.new(".toml", "config-toml")
    assert_equal [".toml", "config-toml"], [disabled.extension, disabled.feature]
    assert_equal "yaml", P::ConfigError::UnsupportedFormat.new("yaml").extension
  end

  def test_a_syntax_error_keeps_serde_jsons_error
    ConfigFixtures.with_case("syntax_error") do |dir|
      error = assert_raises(P::ConfigError::FormatJson) { P.read_from(Target.current, dir) }
      assert_equal File.join(dir, "tokra.conf.json"), error.path
      assert_kind_of Tokra::Ipc::Json::Error, error.error
    end
  end

  def test_read_from_answers_the_paths_it_read
    ConfigFixtures.with_case("platform_merge") do |dir|
      _, paths = P.read_from(Target::MacOS, dir)
      assert_equal [File.join(dir, "tokra.conf.json"), File.join(dir, "tokra.macos.conf.json")], paths
      _, paths = P.read_from(Target::Linux, dir)
      assert_equal [File.join(dir, "tokra.conf.json")], paths
    end
  end

  # Rust displays a path with the platform's separator.
  def test_a_path_displays_with_the_platforms_separator
    expected = windows? ? "C:\\app\\tokra.conf.json" : "C:/app/tokra.conf.json"
    assert_equal expected, P.display("C:/app/tokra.conf.json")
  end

  def test_the_formats_name_their_files
    formats = P::SUPPORTED_FORMATS
    assert_equal %w[tokra.conf.json tokra.conf.json5 Tokra.toml], formats.map(&:into_file_name)
    assert_equal %w[tokra.windows.conf.json tokra.windows.conf.json5 Tokra.windows.toml],
      formats.map { |format| format.into_platform_file_name(Target::Windows) }
    assert_equal [P::ConfigFormat::Json], P::ENABLED_FORMATS
  end

  # Reads the case for the answer's target as get_config does, and checks
  # the macro's check, the error, or the probes against Tauri's answer.
  private def assert_case(name, answer)
    target = ConfigFixtures::TARGETS.fetch(answer.fetch("target"))
    label = "#{name} on #{target.name}"
    ConfigFixtures.with_case(name) do |dir|
      if answer.key?("parse_value")
        assert_outcome(answer, dir, label) { P.parse_value(target, File.join(dir, answer.fetch("parse_value"))).first }
        next
      end
      if answer.key?("check")
        exists = P.does_supported_file_name_exist(target, File.join(dir, answer.fetch("path")))
        assert_equal answer.fetch("check").nil?, exists, label
        next unless exists
      end
      assert_outcome(answer, dir, label) { C::Config.deserialize(P.read_from(target, dir).first, dir) }
    end
  end

  private def assert_outcome(answer, dir, label)
    if answer.key?("error")
      error = assert_raises(P::ConfigError, Tokra::Ipc::CommandItem::Mismatch, label) { yield }
      assert_equal ConfigFixtures.fill(answer.fetch("error"), dir), error.message, label
    else
      probes = answer.fetch("probes")
      expected = ConfigFixtures.fill_all(probes, dir)
      assert_equal expected, ConfigFixtures.probed(yield, probes.keys), label
    end
  end

  private def windows?
    Target.current == Target::Windows
  end
end
