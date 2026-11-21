# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "digest"
require "tokra-global-shortcut"

$LOAD_PATH.unshift File.expand_path("../../../test", __dir__)
require "support/stub_native"
require "support/test_app"

# How an app registers the global-shortcut plugin: Tauri's Builder, whose
# build takes no app, given to Builder#plugin, with no config and its
# global API script (plan 064). Runs a real Tokra::App on StubNative and
# makes no hotkey manager: the tests that do are in test_setup.rb, with the
# real-window ones.
class TestRegistration < Minitest::Test
  G = Tokra::Plugins::GlobalShortcut

  # SHA-256 of plugins/global-shortcut/api-iife.js at plugins-workspace
  # d4613ff0.
  UPSTREAM_API_SCRIPT_SHA256 = "05b5e056955579d34f495dbc410b4f697e3e51ee9dce5ed959ba9a1c9f3b9a68"

  def teardown
    StubNative.clear_event
  end

  def test_build_is_a_tauri_plugin_named_global_shortcut
    plugin = G::Builder.new.build

    assert_instance_of Tokra::Plugin::TauriPlugin, plugin
    assert_equal "global-shortcut", plugin.name, "lib.rs:391"
  end

  def test_the_gem_names_tauris_global_api_script
    path = File.expand_path("../lib/tokra/plugins/global_shortcut/api-iife.js", __dir__)

    assert_includes Tokra::Utils::Plugin.global_api_script_paths, File.realpath(path), "build.rs:9"
    assert_equal UPSTREAM_API_SCRIPT_SHA256, Digest::SHA256.file(path).hexdigest, "upstream's file, unchanged"
  end

  # Tauri's plugin takes no config, so a non-null slice fails the app
  # before the setup that would make a hotkey manager runs.
  def test_a_global_shortcut_config_is_refused_as_tauris_unit_config_is
    builder = Tokra::Builder.default.plugin(G::Builder.new.build)
    app = build_test_app(builder, config: { "plugins" => { "global-shortcut" => {} } })

    error = assert_raises(Tokra::Error::PluginInitialization) { app.run }

    assert_equal "failed to initialize plugin `global-shortcut`: Error deserializing 'plugins.global-shortcut' " \
      "within your Tokra configuration: invalid type: map, expected unit", error.message
    assert_nil app.handle.try_state(G::GlobalShortcut), "no setup ran"
  end
end
