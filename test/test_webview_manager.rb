# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/test_app"

# What WebviewManager reads from the app's config and context: the
# @tauri-apps/api bundle when app.withGlobalTauri is set, as codegen puts
# it in Tauri's context (tauri-codegen context.rs:430-440), and the pattern
# script's object from the context's pattern (manager/webview.rs:131-133;
# pattern.rs:39-63).
class TestWebviewManager < Minitest::Test
  private def manager_for(context, pattern: context.pattern)
    app_manager = Tokra::AppManager.new(config: context.config, package_info: context.package_info, pattern:,
      dev: context.dev, webviews: {}, windows: {})
    Tokra::WebviewManager.new(app_manager, os_name: Tokra::App.os_name)
  end

  def test_with_global_tauri_in_the_config_adds_the_api_bundle_last
    scripts = manager_for(build_test_context(config: { "app" => { "withGlobalTauri" => true } }))
      .initialization_scripts("main", "main")

    assert_includes scripts.last, "__TAURI_IIFE__"
    assert_equal 1, scripts.count { |script| script.include?("__TAURI_IIFE__") }
  end

  def test_without_with_global_tauri_the_api_bundle_is_left_out
    scripts = manager_for(build_test_context).initialization_scripts("main", "main")

    refute(scripts.any? { |script| script.include?("__TAURI_IIFE__") })
  end

  # PatternObject serializes with its tag, "pattern", and the variant in
  # lowercase (pattern.rs:40-45).
  def test_the_pattern_script_is_the_contexts_pattern
    init = manager_for(build_test_context).initialization_scripts("main", "main")[3]

    assert_includes init, JSON.generate({ "pattern" => "brownfield" })
  end

  def test_a_pattern_tokra_does_not_have_is_refused
    manager = manager_for(build_test_context, pattern: :isolation)
    error = assert_raises(TypeError) { manager.initialization_scripts("main", "main") }

    assert_equal "wrong argument type Symbol (expected Tokra::Pattern)", error.message
  end
end
