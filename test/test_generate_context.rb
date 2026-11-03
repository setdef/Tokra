# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/config_fixtures"

# Tokra.generate_context, the translation of Tauri's generate_context!
# macro (ADR 014 §2, §5): where it looks, what it checks, and what it
# answers, held up against the macro's check and tauri-codegen's
# get_config on this machine's platform (test/fixtures/config/cases).
class TestGenerateContext < Minitest::Test
  Parse = Tokra::Utils::Config::Parse

  def setup
    @program = $PROGRAM_NAME
  end

  def teardown
    $PROGRAM_NAME = @program
    Tokra.record_anchor
  end

  # --- a path given, as the macro checks it (context.rs:36-56) ---

  def test_a_given_path_is_checked_and_read_as_the_macro_and_codegen_read_it
    %w[
      platform_file_at_a_given_path
      other_file_at_a_given_path
      missing_file_at_a_given_path
      json5_only_at_a_given_path
].each do |name|
      answer = ConfigFixtures.current_answer(name)
      ConfigFixtures.with_case(name) do |dir|
        path = File.join(dir, answer.fetch("path"))
        if answer.fetch("check")
          error = assert_raises(ArgumentError, name) { Tokra.generate_context(path) }
          assert_equal ConfigFixtures.fill(answer.fetch("check"), dir), error.message, name
        else
          assert_answer(answer, dir, name) { Tokra.generate_context(path) }
        end
      end
    end
  end

  def test_a_relative_path_joins_the_anchor
    ConfigFixtures.with_case("platform_merge") do |dir|
      FileUtils.mkdir_p(File.join(dir, "app"))
      anchor_at(File.join(dir, "app", "main.rb"))
      context = Tokra.generate_context("../tokra.conf.json")
      assert_equal "com.tokra.fixture", context.config.identifier
    end
  end

  def test_a_pathname_is_taken_too
    ConfigFixtures.with_case("platform_merge") do |dir|
      assert_equal "com.tokra.fixture", Tokra.generate_context(Pathname(dir).join("tokra.conf.json")).config.identifier
    end
  end

  def test_a_relative_path_where_no_config_is_names_the_joined_path
    ConfigFixtures.with_case("platform_merge") do |dir|
      anchor_at(File.join(dir, "main.rb"))
      error = assert_raises(ArgumentError) { Tokra.generate_context("nested/tokra.conf.json") }
      assert_equal "no file at path #{Parse.display(File.join(dir, 'nested/tokra.conf.json'))} exists, " \
        "expected tokra config file", error.message
    end
  end

  # --- no path: the anchor's tokra.conf.json, unchecked (context.rs:126-133) ---

  def test_no_path_reads_the_config_beside_the_entry_script
    ConfigFixtures.with_case("platform_merge") do |dir|
      anchor_at(File.join(dir, "main.rb"))
      answer = ConfigFixtures.current_answer("platform_merge")
      assert_answer(answer, dir, "platform_merge") { Tokra.generate_context }
    end
  end

  # The macro does not check its default path, so a missing file is
  # do_parse's Io error (parse.rs:327-333).
  def test_no_path_and_no_file_is_entity_not_found
    ConfigFixtures.with_case("no_file") do |dir|
      anchor_at(File.join(dir, "main.rb"))
      answer = ConfigFixtures.current_answer("no_file")
      error = assert_raises(Parse::ConfigError::Io) { Tokra.generate_context }
      assert_equal ConfigFixtures.fill(answer.fetch("error"), dir), error.message
    end
  end

  def test_a_schema_error_is_codegens_json_error
    ConfigFixtures.with_case("schema_error") do |dir|
      error = assert_raises(Tokra::Codegen::CodegenConfigError::Json) do
        Tokra.generate_context(File.join(dir, "tokra.conf.json"))
      end
      assert_equal ConfigFixtures.current_answer("schema_error").fetch("error"), error.message
      assert_kind_of Tokra::Error, error
    end
  end

  # --- the anchor, taken when tokra loads (plan 054, decision 24) ---

  def test_the_anchor_does_not_move_with_the_working_directory
    ConfigFixtures.with_case("platform_merge") do |dir|
      Dir.chdir(dir) do
        $PROGRAM_NAME = "main.rb"
        File.write("main.rb", "")
        Tokra.record_anchor
      end
      Dir.mktmpdir do |elsewhere|
        Dir.chdir(elsewhere) { assert_equal "com.tokra.fixture", Tokra.generate_context.config.identifier }
      end
    end
  end

  def test_a_symlinked_script_anchors_at_its_targets_directory
    skip "Windows needs a privilege to make a symlink" if Tokra::Utils::Platform::Target.current.name == "Windows"
    ConfigFixtures.with_case("platform_merge") do |dir|
      Dir.mktmpdir do |bin|
        File.write(File.join(dir, "main.rb"), "")
        File.symlink(File.join(dir, "main.rb"), File.join(bin, "launcher"))
        $PROGRAM_NAME = File.join(bin, "launcher")
        Tokra.record_anchor
        assert_equal dir, Tokra.anchor
      end
    end
  end

  def test_a_program_name_that_is_no_file_anchors_at_the_working_directory
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        $PROGRAM_NAME = "-e"
        Tokra.record_anchor
        assert_equal Dir.pwd, Tokra.anchor
      end
    end
  end

  # --- no environment variable (ADR 014 §6) ---

  def test_no_environment_variable_changes_the_config
    ConfigFixtures.with_case("platform_merge") do |dir|
      path = File.join(dir, "tokra.conf.json")
      with_env("TAURI_CONFIG" => '{"identifier":"com.env.tauri"}', "TOKRA_CONFIG" => '{"identifier":"com.env.tokra"}') do
        assert_equal "com.tokra.fixture", Tokra.generate_context(path).config.identifier
      end
    end
  end

  # --- what the context holds ---

  def test_the_context_holds_the_config_package_info_and_pattern
    ConfigFixtures.with_case("version_semver") do |dir|
      context = Tokra.generate_context(File.join(dir, "tokra.conf.json"))
      assert_instance_of Tokra::Context, context
      assert_equal "1.2.3-beta.1+build.5", context.package_info.version
      assert_equal Tokra::Pattern::Brownfield.new, context.pattern
      assert context.dev
    end
  end

  private def anchor_at(script)
    File.write(script, "")
    $PROGRAM_NAME = script
    Tokra.record_anchor
  end

  private def assert_answer(answer, dir, label)
    if answer.key?("error")
      error = assert_raises(Parse::ConfigError, Tokra::Codegen::CodegenConfigError, label) { yield }
      assert_equal ConfigFixtures.fill(answer.fetch("error"), dir), error.message, label
    else
      probes = answer.fetch("probes")
      expected = ConfigFixtures.fill_all(probes, dir)
      assert_equal expected, ConfigFixtures.probed(yield.config, probes.keys), label
    end
  end

  private def with_env(values)
    saved = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
