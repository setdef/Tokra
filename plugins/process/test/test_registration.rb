# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "digest"

# How an app registers the process plugin: Tauri's init(), given to
# Builder#plugin, with no config and its global API script (plan 064).
# Runs a real Tokra::App on StubNative; nothing exits or restarts.
class TestRegistration < Minitest::Test
  include ProcessTest

  # SHA-256 of plugins/process/api-iife.js at plugins-workspace d4613ff0.
  UPSTREAM_API_SCRIPT_SHA256 = "a3dd897bde09030b3eb46030786b7e39db6423ed5c87f862de12eb5aa3984f60"

  def test_init_is_a_tauri_plugin_named_process
    plugin = Tokra::Plugins::Process.init

    assert_instance_of Tokra::Plugin::TauriPlugin, plugin
    assert_equal "process", plugin.name, "lib.rs:20"
  end

  def test_the_global_api_script_is_tauris_file_and_runs_with_with_global_tauri
    path = File.expand_path("../lib/tokra/plugins/process/api-iife.js", __dir__)
    builder = Tokra::Builder.default.plugin(Tokra::Plugins::Process.init)
    app = build_test_app(builder, config: { "app" => { "withGlobalTauri" => true } })

    run_app(app)

    assert_includes Tokra::Utils::Plugin.global_api_script_paths, File.realpath(path), "build.rs:9"
    assert_equal UPSTREAM_API_SCRIPT_SHA256, Digest::SHA256.file(path).hexdigest, "upstream's file, unchanged"
    scripts = app.handle.webviews["main"].native.initialization_scripts
    assert_operator scripts.index(File.read(path)), :>, scripts.index { |script| script.include?("__TAURI_IIFE__") },
      "after Tauri's bundle, whose window.__TAURI__ it extends"
  end

  # Tauri reads a plugin's config only for its setup (plugin.rs:793-806),
  # and the process plugin has none, so a plugins.process value is
  # ignored rather than refused.
  def test_a_process_config_is_ignored_as_tauri_ignores_it
    builder = Tokra::Builder.default.plugin(Tokra::Plugins::Process.init)
    app = build_test_app(builder, config: { "plugins" => { "process" => { "anything" => 1 } } })

    run_app(app)

    assert app.handle.remove_plugin("process"), "the plugin was initialized and kept"
  end
end
