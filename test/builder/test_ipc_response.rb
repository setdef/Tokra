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

  # Tauri reads a postMessage with serde_json::from_str and reports a
  # failure in the page as console.error("JSON error: ...") without
  # running the command (ipc/protocol.rs:287-291, 422-430; error.rs:50-51).
  # Ruby's JSON reads the lone trailing surrogate into a broken string
  # (Plan 032).
  def test_message_serde_json_rejects_is_reported_in_the_page
    Thread.current[:handler_called] = false
    handler = Ractor.shareable_proc { |_invoke| Thread.current[:handler_called] = true }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    StubNative.inject_event(Tokra::Native::IpcEvent.new(
      '{"cmd":"ping","callback":1,"error":2,"payload":{"text":"\udc00"},' \
        "\"__TAURI_INVOKE_KEY__\":\"#{app.invoke_key}\"}",
      LocalOrigin.url(app:)
    ))

    _out, err = capture_subprocess_io { app.run }

    refute Thread.current[:handler_called], "a rejected message must not dispatch the command"
    assert_equal ['console.error("JSON error: lone leading surrogate in hex escape at line 1 column 62")'],
      webview_evals(app)
    assert_empty err
  ensure
    StubNative.clear_event
  end

  # Tauri's Message needs a string cmd (ipc/protocol.rs:233-242), and
  # serde reads the message before on_message checks the key, so a wrong
  # cmd is reported even from a frame with the wrong key.
  def test_message_whose_cmd_is_not_a_string_is_reported_before_the_key_check
    Thread.current[:handler_called] = false
    handler = Ractor.shareable_proc { |_invoke| Thread.current[:handler_called] = true }
    { 5 => "integer `5`", nil => "null" }.each do |cmd, described|
      app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
      StubNative.inject_event(Tokra::Native::IpcEvent.new(JSON.generate(
        { "cmd" => cmd, "callback" => 1, "error" => 2, "__TAURI_INVOKE_KEY__" => "wrong" }
      ), LocalOrigin.url(app:)))
      _out, err = capture_subprocess_io { app.run }

      assert_empty err, "no key mismatch is logged for cmd #{cmd.inspect}"
      assert_equal ["console.error(\"JSON error: invalid type: #{described}, expected a string\")"],
        webview_evals(app)
    end
    refute Thread.current[:handler_called], "a non-string cmd must not dispatch"
  ensure
    StubNative.clear_event
  end

  # The report is the message as serde_json writes a string value, so the
  # backslashes in serde_json's control-character message are escaped.
  def test_message_error_report_is_a_json_string_literal
    app = Tokra::Builder.default.build(native: StubNative)
    StubNative.inject_event(Tokra::Native::IpcEvent.new("{\"cmd\":\"a\tb\"}", LocalOrigin.url(app:)))
    app.run

    assert_equal [
'console.error("JSON error: control character (\\\\u0000-\\\\u001F) found ' \
  'while parsing a string at line 1 column 10")',
], webview_evals(app)
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

  # Records what a command saw over postMessage.
  private def recording_app
    Thread.current[:seen] = nil
    handler = Ractor.shareable_proc { |invoke|
      request = Tokra::Ipc::Request.from_command(invoke)
      Thread.current[:seen] = { body: request.body, payload: invoke.payload, headers: request.headers }
      invoke.resolve(nil)
      true
    }
    Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
  end

  # Over postMessage the client JSON-encodes a Uint8Array as a number
  # array (process-ipc-message-fn.js:26-29), and Tauri's body is that
  # JSON value (ipc/protocol.rs:236, 295), which the fs plugin's
  # write_file accepts beside raw bytes.
  def test_post_message_byte_array_is_a_json_body
    app = recording_app
    inject_ipc(app, "cmd" => "ping", "callback" => 1, "error" => 2, "payload" => [1, 2, 255])
    app.run

    assert_equal [1, 2, 255], Thread.current[:seen][:body]
    assert_equal [1, 2, 255], Thread.current[:seen][:payload]
  ensure
    StubNative.clear_event
  end

  # Tauri reads options.headers into a HeaderMap, names lowercased by the
  # http crate (ipc/protocol.rs:197-229, 297).
  def test_post_message_headers_come_from_options
    app = recording_app
    inject_ipc(app, "cmd" => "ping", "callback" => 1, "error" => 2, "payload" => {},
      "options" => { "headers" => { "Path" => "%2Ftmp", "x-n" => "1" }, "customProtocolIpcBlocked" => true })
    app.run

    assert_equal({ "path" => "%2Ftmp", "x-n" => "1" }, Thread.current[:seen][:headers])
    assert_predicate Thread.current[:seen][:headers], :frozen?

    app = recording_app
    inject_ipc(app, "cmd" => "ping", "callback" => 1, "error" => 2, "payload" => {})
    app.run
    assert_equal({}, Thread.current[:seen][:headers], "no options means no headers")
  ensure
    StubNative.clear_event
  end

  # A header the http crate refuses fails the whole message as a serde
  # error, reported in the page before the key check (ipc/protocol.rs:
  # 206-218; http name.rs:1009-1100, value.rs:585-587).
  def test_post_message_invalid_header_is_reported_in_the_page
    {
      { "bad name" => "v" } => "invalid header `bad name` `v`",
      { "" => "v" } => "invalid header `` `v`",
      { "x" => "line\nbreak" } => "invalid header `x` `line\nbreak`",
      { "x" => "\u007F" } => "invalid header `x` `\u007F`",
      { "x" => 1 } => "invalid type: integer `1`, expected a string",
      "nope" => 'invalid type: string "nope", expected a map',
    }.each do |headers, message|
      Thread.current[:seen] = nil
      app = recording_app
      StubNative.inject_event(Tokra::Native::IpcEvent.new(
        JSON.generate("cmd" => "ping", "callback" => 1, "error" => 2, "payload" => {},
          "options" => { "headers" => headers }, "__TAURI_INVOKE_KEY__" => "wrong"),
        LocalOrigin.url(app:)
      ))
      _out, err = capture_subprocess_io { app.run }

      assert_nil Thread.current[:seen], "#{headers.inspect} must not dispatch"
      assert_equal ["console.error(#{JSON.generate("JSON error: #{message}")})"], webview_evals(app)
      assert_empty err, "the header error comes before the key check"
    end
  ensure
    StubNative.clear_event
  end

  # Header values may hold tabs and bytes past ASCII (value.rs:585-587).
  def test_post_message_header_values_allow_tab_and_non_ascii
    app = recording_app
    inject_ipc(app, "cmd" => "ping", "callback" => 1, "error" => 2, "payload" => {},
      "options" => { "headers" => { "x" => "a\tb é" } })
    app.run

    assert_equal({ "x" => "a\tb é" }, Thread.current[:seen][:headers])
  ensure
    StubNative.clear_event
  end

  # Over postMessage on macOS, and whenever the client fell back from
  # ipc:// (test_ipc_channel_fetch.rb covers the rest), Tauri evaluates a raw response with format_result, which
  # serializes the bytes as a JSON number array (ipc/protocol.rs:390-402).
  def test_raw_response_over_post_message_is_a_number_array
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve(Tokra::Ipc::Response.new("\x03\x02\xFF".b))
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    app.stub(:os_name, "macos") do
      inject_ipc(app, "cmd" => "ping", "callback" => 100, "error" => 200)
      app.run
    end

    assert_equal ["window.__TAURI_INTERNALS__.runCallback(100, [3,2,255])"], webview_evals(app)
  ensure
    StubNative.clear_event
  end

  # responder_eval answers the error callback when the reply cannot be
  # formatted (ipc/protocol.rs:313-325), so the invoke still settles.
  def test_a_reply_that_cannot_be_formatted_rejects_with_the_error
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("pong")
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    inject_ipc(app, "cmd" => "ping", "callback" => 100, "error" => 200)
    format_raw = Tokra::Ipc::FormatCallback.method(:format_raw)
    failing = -> (id, json) { (id == 100) ? raise(ArgumentError, "cannot format") : format_raw.call(id, json) }
    Tokra::Ipc::FormatCallback.stub(:format_raw, failing) { app.run }

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(200, "cannot format")'], webview_evals(app)
  ensure
    StubNative.clear_event
  end
end
