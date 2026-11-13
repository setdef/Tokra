# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"
require_relative "../support/stub_native"
require_relative "../support/test_app"

# Tests the plugins' global API scripts, which a page with withGlobalTauri
# runs after Tauri's own bundle (plan 064, decisions 7 and 12).
#
# A plugin's build script names its api-iife.js (tauri-plugin
# build/mod.rs:61-67, 146-148; tauri-utils plugin.rs:21-30), the app's
# build collects the paths with Tauri's first (tauri-utils plugin.rs:37-60),
# codegen reads them into the Context when the config sets withGlobalTauri
# (tauri-codegen context.rs:430-439), and each webview runs them after the
# plugins' initialization scripts (manager/webview.rs:196, 210-215).
class TestPluginGlobalApiScripts < Minitest::Test
  U = Tokra::Utils::Plugin

  def setup
    @saved = U.global_api_script_paths
    @dir = Dir.mktmpdir
  end

  def teardown
    U.instance_variable_set(:@global_api_script_paths, @saved)
    FileUtils.remove_entry(@dir)
    StubNative.clear_event
  end

  private def script(name, body)
    path = File.join(@dir, name)
    File.write(path, body)
    path
  end

  def test_a_path_is_kept_canonicalized_and_once
    path = script("api-iife.js", "window.one = 1")
    link = File.join(@dir, "link.js")
    File.symlink(path, link)

    U.define_global_api_script_path(link)
    U.define_global_api_script_path(path)

    assert_equal [*@saved, File.realpath(path)], U.global_api_script_paths,
      "canonicalize() resolves the link, and a crate has one key, so a path is named once"
    assert_predicate U.global_api_script_paths, :frozen?
  end

  def test_a_missing_script_is_refused_in_tauris_words
    error = assert_raises(Tokra::Error) { U.define_global_api_script_path(File.join(@dir, "missing.js")) }

    assert_equal "failed to canonicalize global API script path: No such file or directory (os error 2)", error.message
  end

  def test_read_gives_tauris_bundle_first_then_each_script_in_order
    U.define_global_api_script_path(script("a.js", "window.a = 1"))
    U.define_global_api_script_path(script("b.js", "window.b = 2"))

    scripts = U.read_global_api_scripts

    assert_includes scripts.first, "__TAURI_IIFE__", "Tauri's own path is inserted first (tauri-utils plugin.rs:51-53)"
    assert_equal ["window.a = 1", "window.b = 2"], scripts.last(2)
  end

  def test_a_script_that_cannot_be_read_is_reported
    path = script("gone.js", "")
    U.define_global_api_script_path(path)
    File.delete(path)

    error = assert_raises(Tokra::Error) { U.read_global_api_scripts }

    assert_equal "failed to read plugin global API script #{File.realpath(@dir)}/gone.js: No such file or " \
      "directory (os error 2)", error.message
  end

  def test_codegen_reads_them_only_with_with_global_tauri
    U.define_global_api_script_path(script("a.js", "window.a = 1"))

    with = build_test_context(config: { "app" => { "withGlobalTauri" => true } })
    without = build_test_context

    assert_equal "window.a = 1", with.plugin_global_api_scripts.last
    assert_includes with.plugin_global_api_scripts.first, "__TAURI_IIFE__"
    assert_nil without.plugin_global_api_scripts, "codegen writes None without withGlobalTauri"
  end

  def test_a_webview_runs_them_last_in_the_main_frame
    U.define_global_api_script_path(script("a.js", "window.a = 1"))
    plugin = Tokra::Plugin::Builder.new("example").js_init_script("window.example = 1").build
    app = build_test_app(Tokra::Builder.default.plugin(plugin), config: { "app" => { "withGlobalTauri" => true } })

    app.run

    pairs = app.handle.webviews["main"].native.initialization_script_pairs
    assert_equal ["window.a = 1", true], pairs.last
    assert_includes pairs[-2].first, "__TAURI_IIFE__"
    assert_operator pairs.index(["(function () { window.example = 1 })();", true]), :<, pairs.size - 2,
      "the plugins' initialization scripts come first"
  end

  def test_the_context_decides_not_the_config_at_webview_time
    context = build_test_context
    context.config = context.config.with(app: context.config.app.with(with_global_tauri: true))
    app = Tokra::Builder.default.build(context, native: StubNative)

    app.run

    scripts = app.handle.webviews["main"].native.initialization_scripts
    refute(scripts.any? { |script| script.include?("__TAURI_IIFE__") },
      "codegen decided when it read the config, as Tauri's does at compile time")
  end
end
