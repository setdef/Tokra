# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests that Builder#with_global_tauri injects the @tauri-apps/api bundle.
#
# Tauri's withGlobalTauri injects the API's prebuilt IIFE as an
# initialization script so a bundler-less page reaches window.__TAURI__.
# Tokra appends the vendored bundle.global.js after the core init scripts.
class TestBuilderGlobalTauri < Minitest::Test
  private def scripts_for(app)
    StubNative.inject_event(nil)
    app.run
    app.handle.webviews["main"].native.initialization_scripts
  ensure
    StubNative.clear_event
  end

  def test_disabled_by_default_omits_the_api_bundle
    app = Tokra::Builder.default.build(native: StubNative)
    refute(scripts_for(app).any? { |s| s.include?("__TAURI_IIFE__") },
      "without with_global_tauri the API bundle is not injected")
  end

  def test_enabled_appends_the_api_bundle_last
    app = Tokra::Builder.default.with_global_tauri.build(native: StubNative)
    scripts = scripts_for(app)

    assert_includes scripts.last, "__TAURI_IIFE__",
      "the API bundle is injected after the core init scripts"
    assert(scripts.last.include?("window.__TAURI__") || scripts.last.include?("__TAURI__"),
      "the injected bundle exposes the global API object")
  end

  def test_with_global_tauri_returns_self_for_chaining
    builder = Tokra::Builder.default
    assert_same builder, builder.with_global_tauri, "with_global_tauri is chainable"
  end

  def test_with_global_tauri_false_leaves_it_disabled
    app = Tokra::Builder.default.with_global_tauri(false).build(native: StubNative)
    refute(scripts_for(app).any? { |s| s.include?("__TAURI_IIFE__") },
      "passing false keeps the API bundle out")
  end
end
