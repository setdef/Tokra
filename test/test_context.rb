# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Context, Tauri's Context (lib.rs:349-527), and what
# Codegen.context_codegen fills it with: the package information, with
# Cargo's values translated for a Ruby app (plan 054, decision 9), and
# the pattern.
class TestContext < Minitest::Test
  C = Tokra::Utils::Config
  Target = Tokra::Utils::Platform::Target

  def setup
    @program = $PROGRAM_NAME
  end

  def teardown
    $PROGRAM_NAME = @program
    Tokra.record_anchor
  end

  def test_config_writer_stores_a_changed_copy_deep_frozen
    context = context_for({ "identifier" => "com.example.app" })
    changed = context.config.with(identifier: +"com.example.beta")
    context.config = changed
    assert_equal "com.example.beta", context.config.identifier
    assert Ractor.shareable?(context.config)
    assert_raises(TypeError) { context.config = { "identifier" => "x" } }
  end

  def test_package_info_writer_stores_a_changed_copy_deep_frozen
    context = context_for({ "identifier" => "com.example.app" })
    context.package_info = context.package_info.with(version: +"2.0.0")
    assert_equal "2.0.0", context.package_info.version
    assert Ractor.shareable?(context.package_info)
    assert_raises(TypeError) { context.package_info = "2.0.0" }
  end

  def test_new_checks_its_pattern
    context = context_for({ "identifier" => "a" })
    error = assert_raises(TypeError) do
      Tokra::Context.new(config: context.config, default_window_icon: nil, app_icon: nil,
        package_info: context.package_info, pattern: :brownfield)
    end
    assert_equal "wrong argument type Symbol (expected Tokra::Pattern)", error.message
  end

  # codegen's PackageInfo (context.rs:270-289): productName and version
  # when the config has them.
  def test_package_info_comes_from_the_config
    entry("/apps/notes/main.rb")
    info = context_for({ "identifier" => "a", "productName" => "Notes", "version" => "1.4.0" }).package_info
    assert_equal Tokra::Utils::PackageInfo.new(name: "Notes", version: "1.4.0", authors: "", description: "",
      crate_name: "main"), info
  end

  # Without productName and version, Tauri takes Cargo's package name
  # and version; a Ruby app's stand-ins are the entry script's name and
  # Cargo's own default, 0.0.0.
  def test_package_info_falls_back_to_the_entry_script_and_zero
    entry("/apps/notes/notes-app.rb")
    info = context_for({ "identifier" => "a" }).package_info
    assert_equal ["notes-app", "0.0.0", "", "", "notes-app"],
      [info.name, info.version, info.authors, info.description, info.crate_name]
  end

  # The script's name is taken when tokra loads, with the anchor, so a
  # program that renames itself later keeps its package name.
  def test_a_later_program_name_does_not_rename_the_package
    entry("/apps/notes/notes-app.rb")
    $PROGRAM_NAME = "renamed"
    assert_equal "notes-app", context_for({ "identifier" => "a" }).package_info.name
  end

  # Without the isolation feature, codegen reads either pattern as
  # Brownfield (context.rs:354-359; plan 054, decision 21).
  def test_the_pattern_is_brownfield_for_either_config_pattern
    isolation = {
"identifier" => "a",
"app" => {
"security" => {
"pattern" => {
"use" => "isolation",
"options" => { "dir" => "iso" },
},
},
},
}
    assert_equal Tokra::Pattern::Brownfield.new, context_for(isolation).pattern
    assert_equal Tokra::Pattern::Brownfield.new, context_for({ "identifier" => "a" }).pattern
  end

  def test_context_data_carries_dev_to_the_context
    config = C::Config.new(identifier: "a")
    context = Tokra::Codegen.context_codegen(Tokra::Codegen::ContextData.new(dev: false, config:,
      config_parent: TestApp::CONFIG_PARENT))
    refute context.dev
  end

  def test_package_info_is_reached_at_the_root_as_tauri_reexports_it
    assert_same Tokra::Utils::PackageInfo, Tokra::PackageInfo
  end

  # --- Target.current: platform.rs:75-87 falls through to Linux ---

  def test_target_current_falls_through_to_linux_on_the_bsds
    assert_equal Target::Linux, Target.for_ruby_platform("x86_64-freebsd14")
    assert_equal Target::Linux, Target.for_ruby_platform("x86_64-openbsd7.5")
    assert_equal Target::Linux, Target.for_ruby_platform("x86_64-linux")
    assert_equal Target::MacOS, Target.for_ruby_platform("arm64-darwin24")
    assert_equal Target::Windows, Target.for_ruby_platform("x64-mingw-ucrt")
    assert_equal Target::Windows, Target.for_ruby_platform("x64-mswin64_140")
  end

  def test_target_current_reads_this_rubys_platform
    assert_equal Target.for_ruby_platform(RUBY_PLATFORM), Target.current
  end

  private def entry(script)
    $PROGRAM_NAME = script
    Tokra.record_anchor
  end

  private def context_for(json)
    config = C::Config.deserialize(json, TestApp::CONFIG_PARENT)
    Tokra::Codegen.context_codegen(Tokra::Codegen::ContextData.new(dev: true, config:,
      config_parent: TestApp::CONFIG_PARENT))
  end
end
