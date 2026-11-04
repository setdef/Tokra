# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"
require_relative "../support/test_app"

# Tests that the config's app.withGlobalTauri injects the @tauri-apps/api
# bundle.
#
# Tauri's withGlobalTauri injects the API's prebuilt IIFE as an
# initialization script so a bundler-less page reaches window.__TAURI__
# (tauri-codegen context.rs:430-440). Tokra appends the vendored
# bundle.global.js after the core init scripts.
class TestBuilderGlobalTauri < Minitest::Test
  private def scripts_for(app)
    StubNative.inject_event(nil)
    app.run
    app.handle.webviews["main"].native.initialization_scripts
  ensure
    StubNative.clear_event
  end

  def test_disabled_by_default_omits_the_api_bundle
    app = build_test_app
    refute(scripts_for(app).any? { |s| s.include?("__TAURI_IIFE__") },
      "without withGlobalTauri the API bundle is not injected")
  end

  def test_enabled_appends_the_api_bundle_last
    app = build_test_app(config: { "app" => { "withGlobalTauri" => true } })
    scripts = scripts_for(app)

    assert_includes scripts.last, "__TAURI_IIFE__",
      "the API bundle is injected after the core init scripts"
    assert(scripts.last.include?("window.__TAURI__") || scripts.last.include?("__TAURI__"),
      "the injected bundle exposes the global API object")
  end

  # The kebab-case alias Tauri's schema takes (config.rs:2761-2762).
  def test_the_kebab_case_alias_enables_it_too
    app = build_test_app(config: { "app" => { "with-global-tauri" => true } })
    assert_includes scripts_for(app).last, "__TAURI_IIFE__"
  end

  def test_with_global_tauri_false_leaves_it_disabled
    app = build_test_app(config: { "app" => { "withGlobalTauri" => false } })
    refute(scripts_for(app).any? { |s| s.include?("__TAURI_IIFE__") },
      "false keeps the API bundle out")
  end
end
