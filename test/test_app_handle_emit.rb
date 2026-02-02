# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tests for AppHandle#emit (required for TargetKind::Webview).
#
# Per ADR 005, AppHandle#emit is Ruby that calls:
#   1. Tokra::Native.emit_js_script(event, payload) -> returns JS string
#   2. webviews.each_value { |wv| wv.eval(js) }
class TestAppHandleEmit < Minitest::Test
  def test_emit_calls_eval_on_each_webview
    webview1 = Minitest::Mock.new
    webview2 = Minitest::Mock.new
    webviews = { "main" => webview1, "secondary" => webview2 }

    config = Tokra::Config.new(
      identifier: "com.example.test",
      product_name: "Test App",
      version: "1.0.0"
    )
    manager = Tokra::AppManager.new(config:, webviews:, windows: {})
    handle = Tokra::AppHandle.new(manager)

    # Stub Native.emit_js_script to return JS containing event and payload
    Tokra::Native.stub(:emit_js_script, -> (event, payload) { "emit('#{event}', #{payload})" }) do
      # Expect eval to be called with JS containing event and payload
      webview1.expect(:eval, nil) { |js| js.include?("log://log") && js.include?("hello") }
      webview2.expect(:eval, nil) { |js| js.include?("log://log") && js.include?("hello") }

      handle.emit("log://log", { message: "hello" })

      webview1.verify
      webview2.verify
    end
  end

  def test_emit_js_script_generates_valid_javascript
    js = Tokra::Native.emit_js_script("log://log", '{"message":"hello"}')

    # Verify it's a self-executing function
    assert_match(/^\(function \(\)/, js)
    assert_match(/\)\(\)$/, js)

    # Verify it contains the event and payload
    assert_includes js, "log://log"
    assert_includes js, '{"message":"hello"}'

    # Verify it uses Tauri's emit function name
    assert_includes js, "__TAURI_EMIT__"
  end

  def test_load_js_template_development_error_mentions_rake
    # Stub File.exist? to simulate missing template in development checkout
    error = nil
    File.stub(:exist?, -> (path) { path.include?("Rakefile") }) do
      error = assert_raises(LoadError) do
        Tokra::Native.load_js_template("nonexistent.js.erb")
      end
    end

    assert_includes error.message, "bundle exec rake sync:tauri"
  end
end
