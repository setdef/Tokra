# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"
require "digest"

# How an app registers the dialog plugin: Tauri's init(), given to
# Builder#plugin, with no config and its global API script (plan 064).
# Runs a real Tokra::App on StubNative; no dialog opens.
class TestRegistration < Minitest::Test
  include DialogTest

  # SHA-256 of plugins/dialog/api-iife.js at plugins-workspace d4613ff0.
  UPSTREAM_API_SCRIPT_SHA256 = "e64d5b3bbe9779115754b9a8f44e0a927dc9a28957443443dd2950f7ba712b3f"

  def teardown
    StubNative.clear_event
  end

  def test_init_is_a_tauri_plugin_named_dialog
    plugin = Dialog.init

    assert_instance_of Tokra::Plugin::TauriPlugin, plugin
    assert_equal "dialog", plugin.name, "lib.rs:187"
  end

  def test_builder_plugin_manages_the_dialog_and_runs_the_init_script_in_main
    app = build_test_app(Tokra::Builder.default.plugin(Dialog.init))

    app.run

    assert_instance_of Dialog::Dialog, app.handle.dialog
    scripts = app.handle.webviews["main"].native.initialization_scripts
    assert_includes scripts, "(function () { #{Dialog::INIT_SCRIPT} })();"
  end

  def test_the_global_api_script_is_tauris_file_and_runs_with_with_global_tauri
    path = File.expand_path("../lib/tokra/plugins/dialog/api-iife.js", __dir__)
    app = build_test_app(Tokra::Builder.default.plugin(Dialog.init), config: { "app" => { "withGlobalTauri" => true } })

    app.run

    assert_includes Tokra::Utils::Plugin.global_api_script_paths, File.realpath(path)
    assert_equal UPSTREAM_API_SCRIPT_SHA256, Digest::SHA256.file(path).hexdigest, "upstream's file, unchanged"
    scripts = app.handle.webviews["main"].native.initialization_scripts
    assert_includes scripts, File.read(path)
    assert_operator scripts.index(File.read(path)), :>, scripts.index { |script| script.include?("__TAURI_IIFE__") },
      "after Tauri's bundle, whose window.__TAURI__ it extends"
  end

  def test_a_dialog_config_is_refused_as_tauris_unit_config_is
    app = build_test_app(Tokra::Builder.default.plugin(Dialog.init), config: { "plugins" => { "dialog" => {} } })

    error = assert_raises(Tokra::Error::PluginInitialization) { app.run }

    assert_equal "failed to initialize plugin `dialog`: Error deserializing 'plugins.dialog' within your Tokra " \
      "configuration: invalid type: map, expected unit", error.message
  end
end
