# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests the initialization scripts App hands the webview.
#
# Tauri assembles them in a fixed order (manager/webview.rs:160-215): the
# __TAURI_INTERNALS__ bootstrap, the invoke transport, webview metadata,
# the init.js bundle, every plugin's initialization script wrapped in an
# IIFE, then the global API bundle when withGlobalTauri is set.
class TestBuilderInitializationScripts < Minitest::Test
  # Plugin contributing an initialization script.
  class ScriptPlugin < Tokra::Plugin
    def initialize(app, name, script)
      super(app)
      @name = name
      @script = script
    end

    attr_reader :name

    def initialization_script = @script
  end

  private def scripts_for(app)
    StubNative.inject_event(nil)
    app.run
    app.handle.webviews["main"].native.initialization_scripts
  ensure
    StubNative.clear_event
  end

  def test_core_scripts_come_in_tauris_order
    app = Tokra::Builder.default.build(native: StubNative)
    scripts = scripts_for(app)

    assert_equal 4, scripts.size, "bootstrap, invoke transport, metadata, init.js"
    assert_includes scripts[0], "Object.defineProperty(window, 'isTauri'"
    assert_includes scripts[0], "Object.defineProperty(window, '__TAURI_INTERNALS__'"
    assert_includes scripts[1], "Object.defineProperty(window.__TAURI_INTERNALS__, 'postMessage'"
    assert_includes scripts[2], "Object.defineProperty(window.__TAURI_INTERNALS__, 'metadata'"
    assert_includes scripts[2], 'currentWindow: { label: "main" }'
    assert_includes scripts[3], "Object.defineProperty(window.__TAURI_INTERNALS__, 'invoke'", "init.js carries core.js"
    assert_includes scripts[3], "Object.defineProperty(window, '__TAURI_EMIT__'", "init.js carries the event script"
  end

  def test_invoke_key_is_templated_into_the_transport_only
    app = Tokra::Builder.default.build(native: StubNative)
    scripts = scripts_for(app)

    assert_includes scripts[1], "const __TAURI_INVOKE_KEY__ = #{JSON.generate(app.invoke_key)}"
    scripts.each_with_index do |script, index|
      next if index == 1

      refute_includes script, app.invoke_key, "script #{index} must not leak the key"
    end
  end

  def test_no_template_markers_survive_rendering
    plugin_app = Tokra::Builder.default.with_global_tauri.build(native: StubNative)
    scripts_for(plugin_app).each_with_index do |script, index|
      refute_match(/__(TEMPLATE|RAW)_\w+__/, script, "script #{index} has a Tauri marker left")
      refute_includes script, "<%", "script #{index} has an ERB tag left"
      refute_match(%r{\A// Auto-generated}, script, "script #{index} kept the vendoring banner")
    end
  end

  def test_plugin_scripts_follow_init_js_wrapped_in_iifes_before_the_api_bundle
    app = Tokra::Builder.default.with_global_tauri.build(native: StubNative)
    app.handle.plugin(ScriptPlugin.new(app.handle, "first", "window.first = 1"))
    app.handle.plugin(ScriptPlugin.new(app.handle, "silent", nil))
    app.handle.plugin(ScriptPlugin.new(app.handle, "second", "window.second = 2"))
    scripts = scripts_for(app)

    assert_equal 7, scripts.size, "four core scripts, two plugin scripts, the API bundle"
    assert_includes scripts[3], "Object.defineProperty(window.__TAURI_INTERNALS__, 'invoke'", "init.js precedes plugin scripts"
    assert_equal "(function () { window.first = 1 })();", scripts[4]
    assert_equal "(function () { window.second = 2 })();", scripts[5],
      "plugins contribute in registration order and nil contributes nothing"
    assert_includes scripts[6], "__TAURI_IIFE__", "the API bundle comes last"
  end

  def test_core_plugins_contribute_no_scripts
    app = Tokra::Builder.default.build(native: StubNative)

    assert_empty app.handle.__send__(:manager).plugins.initialization_script,
      "the resources and image plugins inject nothing"
  end
end
