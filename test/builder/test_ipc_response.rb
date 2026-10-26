# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/local_origin"
require_relative "../support/stub_native"

# Tests that IPC responses reach the WebView.
#
# The dispatcher evaluates Tauri's runCallback script in the calling
# webview: success targets the callback id, failure the error id. Mirrors
# responder_eval (ipc/protocol.rs).
class TestBuilderIpcResponse < Minitest::Test
  private def inject_ipc(app, message, url = LocalOrigin.url(app:))
    StubNative.inject_event(Tokra::Native::IpcEvent.new(
      JSON.generate(message.merge("__TAURI_INVOKE_KEY__" => app.invoke_key)),
      url
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
    ),
      LocalOrigin.url(app:)
    ))

    _out, err = capture_subprocess_io { app.run }

    refute Thread.current[:handler_called], "a mismatched key must not dispatch the command"
    assert_empty webview_evals(app), "a mismatched key must not respond"
    assert_match(/__TAURI_INVOKE_KEY__ expected .* but received wrong/, err,
      "a mismatched key should log to stderr, like Tauri")
  ensure
    StubNative.clear_event
  end

  # wry passes the posting frame's URL; Tauri uses it as the invoke origin.
  # Until capabilities land, a foreign page is denied (Plan 016 #10).
  def test_foreign_page_is_rejected_through_error_id
    Thread.current[:handler_called] = false
    handler = Ractor.shareable_proc { |_invoke| Thread.current[:handler_called] = true }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, { "cmd" => "ping", "callback" => 1, "error" => 2 }, "https://evil.example/page")

    app.run

    refute Thread.current[:handler_called], "a foreign page must not reach the handler"
    assert_equal ['window.__TAURI_INTERNALS__.runCallback(2, "Command ping not allowed by ACL")'],
      webview_evals(app)
  ensure
    StubNative.clear_event
  end

  def test_unparseable_page_url_is_foreign
    app = Tokra::Builder.default.build(native: StubNative)
    inject_ipc(app, { "cmd" => "ping", "callback" => 1, "error" => 2 }, "not a url at all")

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(2, "Command ping not allowed by ACL")'],
      webview_evals(app)
  ensure
    StubNative.clear_event
  end

  def test_page_in_app_with_path_and_uppercase_scheme_is_local
    app = Tokra::Builder.default.build(native: StubNative)
    inject_ipc(app, { "cmd" => "missing", "callback" => 1, "error" => 2 },
      "#{LocalOrigin.url(app:).upcase.delete_suffix('/')}/deep/page?x=1")

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(2, "Command missing not found")'],
      webview_evals(app), "scheme and host compare case-insensitively, like the url crate"
  ensure
    StubNative.clear_event
  end

  def test_handler_exception_rejects_through_error_id
    handler = Ractor.shareable_proc { |_invoke| raise "kaput" }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "explode", "callback" => 1, "error" => 2)

    _out, err = capture_subprocess_io { app.run }

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(2, "kaput")'], webview_evals(app)
    assert_match(/command explode failed: RuntimeError: kaput/, err)
  ensure
    StubNative.clear_event
  end

  def test_unserializable_value_rejects_through_error_id
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("\xFF".b)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "bytes", "callback" => 1, "error" => 2)

    app.run

    assert_equal 1, webview_evals(app).size
    assert webview_evals(app).first.start_with?(%q{window.__TAURI_INTERNALS__.runCallback(2, "}),
      "a value JSON cannot encode rejects with the serializer message"
  ensure
    StubNative.clear_event
  end

  # serde_json writes non-finite floats as null (ser.rs:157-174), so Tauri
  # resolves them rather than rejecting.
  def test_non_finite_floats_resolve_as_null
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve({ "nan" => Float::NAN, "values" => [1.5, Float::INFINITY, -Float::INFINITY] })
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "floats", "callback" => 1, "error" => 2)

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(1, {"nan":null,"values":[1.5,null,null]})'],
      webview_evals(app)
  ensure
    StubNative.clear_event
  end

  def test_bare_nan_resolves_as_null
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve(Float::NAN)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "nan", "callback" => 1, "error" => 2)

    app.run

    assert_equal ["window.__TAURI_INTERNALS__.runCallback(1, null)"], webview_evals(app)
  ensure
    StubNative.clear_event
  end

  # Serialization that raises must still settle the invoke: route_invoke's
  # fallback reject is a no-op once the invoke counts as responded.
  def test_value_whose_to_json_raises_rejects_through_error_id
    handler = Ractor.shareable_proc { |invoke|
      exploding = Object.new
      def exploding.to_json(*) = raise("to_json exploded")
      invoke.resolve([exploding])
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "explode", "callback" => 1, "error" => 2)

    app.run

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(2, "to_json exploded")'], webview_evals(app)
  ensure
    StubNative.clear_event
  end
end
