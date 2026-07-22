# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests that IPC responses reach the WebView.
#
# The dispatcher evaluates Tauri's runCallback script in the calling
# webview: success targets the callback id, failure the error id. Mirrors
# responder_eval (ipc/protocol.rs).
class TestBuilderIpcResponse < Minitest::Test
  private def inject_ipc(app, message)
    StubNative.inject_event(Tokra::Native::IpcEvent.new(
      JSON.generate(message.merge("__TAURI_INVOKE_KEY__" => app.invoke_key))
    ))
  end

  private def webview_evals(app)
    app.handle.webviews["main"].native.evals
  end

  def test_resolution_evaluates_callback_id
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("pong")
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "ping", "callback" => 100, "error" => 200)

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(100, "pong")'],
      webview_evals(app), "resolve should eval runCallback against the callback id"
  ensure
    StubNative.clear_event
  end

  def test_rejection_evaluates_error_id
    handler = Ractor.shareable_proc { |invoke|
      invoke.reject("nope")
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "ping", "callback" => 100, "error" => 200)

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(200, "nope")'],
      webview_evals(app), "reject should eval runCallback against the error id"
  ensure
    StubNative.clear_event
  end

  def test_unhandled_command_rejects_through_error_id
    app = Tokra::Builder.default.build(native: StubNative)
    inject_ipc(app, "cmd" => "missing", "callback" => 1, "error" => 2)

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(2, "Command missing not found")'],
      webview_evals(app), "an unclaimed command should reject to the frontend"
  ensure
    StubNative.clear_event
  end

  def test_core_image_plugin_resolves_rid_to_the_webview
    app = Tokra::Builder.default.build(native: StubNative)
    inject_ipc(app,
      "cmd" => "plugin:image|new",
      "callback" => 55,
      "error" => 66,
      "payload" => { "rgba" => [255, 0, 0, 255], "width" => 1, "height" => 1 })

    app.run

    rid = app.handle.webviews["main"].resources_table.names.to_a.first[0]
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(55, #{rid})"],
      webview_evals(app), "plugin:image|new should resolve its rid through the callback"
  ensure
    StubNative.clear_event
  end

  def test_message_without_callback_ids_is_fire_and_forget
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("ignored")
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    # A hand-rolled window.ipc.postMessage without callback ids
    inject_ipc(app, "cmd" => "ping")

    app.run

    assert_empty webview_evals(app),
      "a message without integer callback ids should not eval anything"
  ensure
    StubNative.clear_event
  end

  def test_mismatched_invoke_key_is_dropped_without_response
    Thread.current[:handler_called] = false
    handler = Ractor.shareable_proc { |_invoke| Thread.current[:handler_called] = true }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    # Deliberately wrong key
    StubNative.inject_event(Tokra::Native::IpcEvent.new(JSON.generate(
      { "cmd" => "ping", "callback" => 1, "error" => 2, "__TAURI_INVOKE_KEY__" => "wrong" }
    )))

    _out, err = capture_subprocess_io { app.run }

    refute Thread.current[:handler_called], "a mismatched key must not dispatch the command"
    assert_empty webview_evals(app), "a mismatched key must not respond"
    assert_match(/__TAURI_INVOKE_KEY__ expected .* but received wrong/, err,
      "a mismatched key should log to stderr, like Tauri")
  ensure
    StubNative.clear_event
  end
end
