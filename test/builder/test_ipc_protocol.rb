# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests the ipc:// custom-protocol transport (Plan 015).
#
# The requests here mirror what Tauri's vendored ipc-protocol.js actually
# sends: a POST to ipc://localhost/<cmd> carrying the payload as the body
# and the Tauri-Callback / Tauri-Error / Tauri-Invoke-Key headers plus
# Content-Type and Origin. The App answers over HTTP (Tauri-Response header
# + JSON body), rather than evaluating runCallback, because the client reads
# the response and calls runCallback itself. Header names, the URL shape,
# and the two failure modes come from ipc/protocol.rs and webview/mod.rs.
class TestBuilderIpcProtocol < Minitest::Test
  # Builds an HttpRequestEvent shaped like an ipc-protocol.js request.
  # +omit+ drops named headers to exercise the malformed paths.
  private def ipc_request(app, cmd:, method: "POST", body: "{}", callback: "100",
    error: "200", key: :app, content_type: "application/json",
    origin: "tokra://localhost", uri: nil, omit: [], lowercase: false
  )
    headers = [] #: Array[[String, String]]
    headers << ["Content-Type", content_type] unless omit.include?(:content_type)
    headers << ["Tauri-Callback", callback] unless omit.include?(:callback)
    headers << ["Tauri-Error", error] unless omit.include?(:error)
    invoke_key = (key == :app) ? app.invoke_key : key
    headers << ["Tauri-Invoke-Key", invoke_key] unless omit.include?(:invoke_key)
    headers << ["Origin", origin] unless omit.include?(:origin)
    # The http crate wry builds requests with lowercases every header name.
    headers = headers.map { |(name, value)| [name.downcase, value] } if lowercase

    Tokra::Native::HttpRequestEvent.new(
      request_id: 7,
      method:,
      uri: uri || "ipc://localhost/#{cmd}",
      headers:,
      body:
    )
  end

  private def run_with(app, event)
    StubNative.inject_event(event)
    app.run
  end

  private def last_response
    StubNative.responses.last
  end

  def test_invoke_round_trips_over_http
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("PONG: #{invoke.payload['message']}")
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", body: JSON.generate("message" => "hi")))

    id, status, headers, body = last_response
    h = headers.to_h
    assert_equal 7, id, "the response targets the originating request id"
    assert_equal 200, status, "invoke replies are 200 for ok and error alike"
    assert_equal "ok", h["Tauri-Response"], "a resolved invoke stamps Tauri-Response: ok"
    assert_equal "application/json", h["Content-Type"]
    assert_equal "*", h["Access-Control-Allow-Origin"], "every reply exposes CORS"
    assert_equal "Tauri-Response", h["Access-Control-Expose-Headers"]
    assert_equal '"PONG: hi"', body, "the JSON-encoded resolved value is the body"
    assert_empty webview_evals(app), "the ipc:// transport answers HTTP, it does not eval"
  ensure
    StubNative.clear_event
  end

  def test_percent_encoded_plugin_command_resolves_rid
    app = Tokra::Builder.default.build(native: StubNative)
    # convertFileSrc percent-encodes the whole command into the path.
    run_with(app, ipc_request(app,
      cmd: "plugin:image|new",
      uri: "ipc://localhost/plugin%3Aimage%7Cnew",
      body: JSON.generate("rgba" => [255, 0, 0, 255], "width" => 1, "height" => 1)))

    rid = app.handle.webviews["main"].resources_table.names.to_a.first[0]
    _id, status, headers, body = last_response
    assert_equal 200, status
    assert_equal "ok", headers.to_h["Tauri-Response"]
    assert_equal rid.to_s, body, "plugin:image|new resolves its rid as a JSON integer"
  ensure
    StubNative.clear_event
  end

  def test_unhandled_command_rejects_with_error_response
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "missing"))

    _id, status, headers, body = last_response
    assert_equal 200, status, "a rejection is still HTTP 200"
    assert_equal "error", headers.to_h["Tauri-Response"], "rejection stamps Tauri-Response: error"
    assert_equal '"Command missing not found"', body, "the error value serializes as JSON"
  ensure
    StubNative.clear_event
  end

  def test_missing_callback_header_is_malformed_500
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", omit: [:callback]))

    _id, status, headers, body = last_response
    assert_equal 500, status, "a malformed request replies 500"
    assert_equal "text/plain", headers.to_h["Content-Type"]
    assert_equal "*", headers.to_h["Access-Control-Allow-Origin"], "even a 500 carries CORS"
    assert_equal "missing Tauri-Callback header", body, "the parse error is the body"
  ensure
    StubNative.clear_event
  end

  def test_non_numeric_callback_header_is_malformed_500
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", callback: "abc"))

    _id, status, _headers, body = last_response
    assert_equal 500, status
    assert_equal "Tauri callback header value must be a numeric string", body
  ensure
    StubNative.clear_event
  end

  def test_unimplemented_content_type_is_malformed_500
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", content_type: "text/plain", body: "hello"))

    _id, status, _headers, body = last_response
    assert_equal 500, status
    assert_equal "content type text/plain is not implemented", body
  ensure
    StubNative.clear_event
  end

  def test_key_mismatch_drops_without_replying
    Thread.current[:handler_called] = false
    handler = Ractor.shareable_proc { |_invoke| Thread.current[:handler_called] = true }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)

    _out, err = capture_subprocess_io do
      run_with(app, ipc_request(app, cmd: "ping", key: "wrong"))
    end

    refute Thread.current[:handler_called], "a mismatched key must not dispatch"
    assert_empty StubNative.responses, "a mismatched key must not reply"
    assert_includes StubNative.dropped, 7, "the responder is dropped by request id"
    assert_match(/__TAURI_INVOKE_KEY__ expected .* but received wrong/, err,
      "a mismatched key logs Tauri's exact message to stderr")
  ensure
    StubNative.clear_event
  end

  def test_options_request_is_a_cors_preflight
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", method: "OPTIONS", body: ""))

    _id, status, headers, body = last_response
    h = headers.to_h
    assert_equal 200, status
    assert_equal "*", h["Access-Control-Allow-Headers"], "preflight allows any header"
    assert_equal "*", h["Access-Control-Allow-Origin"]
    assert_equal "Tauri-Response", h["Access-Control-Expose-Headers"]
    assert_equal "", body, "a preflight has an empty body"
  ensure
    StubNative.clear_event
  end

  def test_non_post_method_is_405
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", method: "GET", body: ""))

    _id, status, headers, body = last_response
    assert_equal 405, status
    assert_equal "text/plain", headers.to_h["Content-Type"]
    assert_equal "only POST and OPTIONS are allowed", body
  ensure
    StubNative.clear_event
  end

  # Real wry hands Ruby lowercase header names (the http crate normalizes
  # them), so every Tauri-* lookup must be case-insensitive.
  def test_lowercase_header_names_round_trip
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve(invoke.payload["n"] + 1)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "inc", body: '{"n":41}', lowercase: true))

    _id, status, headers, body = last_response
    assert_equal 200, status
    assert_equal "ok", headers.to_h["Tauri-Response"]
    assert_equal "42", body
  ensure
    StubNative.clear_event
  end

  # One test per Err arm of parse_invoke_request (ipc/protocol.rs:435-538).
  {
    error: "missing Tauri-Error header",
    invoke_key: "missing Tauri-Invoke-Key header",
    origin: "missing Origin header",
  }.each do |header, message|
    define_method(:"test_missing_#{header}_header_is_malformed_500") do
      app = Tokra::Builder.default.build(native: StubNative)
      run_with(app, ipc_request(app, cmd: "ping", omit: [header]))

      _id, status, headers, body = last_response
      assert_equal 500, status
      assert_equal "text/plain", headers.to_h["Content-Type"]
      assert_equal message, body
    ensure
      StubNative.clear_event
    end
  end

  def test_origin_that_is_not_a_url_is_malformed_500
    app = Tokra::Builder.default.build(native: StubNative)
    # Sandboxed frames send the opaque origin "null", which is no URL.
    run_with(app, ipc_request(app, cmd: "ping", origin: "null"))

    _id, status, _headers, body = last_response
    assert_equal 500, status
    assert_equal "Origin header is not a valid URL", body
  ensure
    StubNative.clear_event
  end

  def test_invalid_json_body_is_malformed_500
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", body: "{not json"))

    _id, status, headers, body = last_response
    assert_equal 500, status
    assert_equal "text/plain", headers.to_h["Content-Type"]
    refute_empty body, "the parser message is the body"
  ensure
    StubNative.clear_event
  end

  def test_non_empty_octet_stream_body_is_malformed_500
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", content_type: "application/octet-stream",
      body: "\x00\x01".b))

    _id, status, _headers, body = last_response
    assert_equal 500, status
    assert_equal "raw request bodies are not implemented", body
  ensure
    StubNative.clear_event
  end

  def test_missing_content_type_defaults_to_octet_stream
    Thread.current[:payload] = nil
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:payload] = invoke.payload
      invoke.resolve(nil)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    # A non-empty body proves the default is octet-stream, not JSON.
    run_with(app, ipc_request(app, cmd: "ping", body: "{}", omit: [:content_type]))
    _id, status, _headers, body = last_response
    assert_equal 500, status
    assert_equal "raw request bodies are not implemented", body

    # An empty body is the payload-less invoke.
    run_with(app, ipc_request(app, cmd: "ping", body: "", omit: [:content_type]))
    _id, status, headers, = last_response
    assert_equal 200, status
    assert_equal "ok", headers.to_h["Tauri-Response"]
    assert_equal({}, Thread.current[:payload])
  ensure
    StubNative.clear_event
  end

  def test_empty_json_body_is_the_empty_object
    Thread.current[:payload] = nil
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:payload] = invoke.payload
      invoke.resolve(nil)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", body: ""))

    assert_equal({}, Thread.current[:payload])
    assert_equal "null", last_response[3], "resolving nil serializes as JSON null"
  ensure
    StubNative.clear_event
  end

  def test_non_object_json_payload_is_the_empty_object
    Thread.current[:payload] = nil
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:payload] = invoke.payload
      invoke.resolve(nil)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", body: "[1, 2]"))

    assert_equal({}, Thread.current[:payload], "handlers index payloads by key (Plan 016 #15)")
  ensure
    StubNative.clear_event
  end

  def test_json_body_bytes_are_parsed_as_utf8
    Thread.current[:payload] = nil
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:payload] = invoke.payload
      invoke.resolve(invoke.payload["text"])
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    # The native layer delivers bodies as binary strings of the exact bytes.
    run_with(app, ipc_request(app, cmd: "echo", body: '{"text":"こんにちは"}'.b))

    assert_equal "こんにちは", Thread.current[:payload]["text"]
    assert_equal '"こんにちは"', last_response[3]
  ensure
    StubNative.clear_event
  end

  # mime's PartialEq compares parameters, so Tauri does not treat a
  # charset-qualified type as JSON.
  def test_content_type_parameters_are_not_stripped
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", content_type: "application/json; charset=utf-8"))

    _id, status, _headers, body = last_response
    assert_equal 500, status
    assert_equal "content type application/json; charset=utf-8 is not implemented", body
  ensure
    StubNative.clear_event
  end

  def test_content_type_essence_is_case_insensitive
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "missing", content_type: "Application/JSON"))

    assert_equal 200, last_response[1], "Application/JSON is application/json"
  ensure
    StubNative.clear_event
  end

  def test_unparseable_content_type_is_unknown
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", content_type: "garbage"))

    _id, status, _headers, body = last_response
    assert_equal 500, status
    assert_equal "unknown content type", body
  ensure
    StubNative.clear_event
  end

  # Rust's u32::from_str: an optional +, ASCII digits, within range.
  ["+12", "0", "4294967295"].each do |id|
    define_method(:"test_callback_id_#{id.delete('+')}_is_a_valid_u32") do
      app = Tokra::Builder.default.build(native: StubNative)
      run_with(app, ipc_request(app, cmd: "missing", callback: id, error: id))

      assert_equal 200, last_response[1], "#{id.inspect} parses as a u32"
    ensure
      StubNative.clear_event
    end
  end

  [" 12 ", "-5", "1_0", "4294967296", "", "0x1F"].each_with_index do |id, index|
    define_method(:"test_callback_id_variant_#{index}_is_not_a_u32") do
      app = Tokra::Builder.default.build(native: StubNative)
      run_with(app, ipc_request(app, cmd: "ping", callback: id))
      _id, status, _headers, body = last_response
      assert_equal 500, status, "#{id.inspect} is not a u32"
      assert_equal "Tauri callback header value must be a numeric string", body

      run_with(app, ipc_request(app, cmd: "ping", error: id))
      assert_equal "Tauri error header value must be a numeric string", last_response[3]
    ensure
      StubNative.clear_event
    end
  end

  def test_405_carries_cors_headers
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", method: "PUT", body: ""))

    h = last_response[2].to_h
    assert_equal 405, last_response[1]
    assert_equal "*", h["Access-Control-Allow-Origin"]
    assert_equal "Tauri-Response", h["Access-Control-Expose-Headers"]
  ensure
    StubNative.clear_event
  end

  # Until capabilities land, only the app's own origin may invoke (Plan 016
  # #10), and a denial reads like Tauri's release-build ACL rejection.
  def test_foreign_origin_is_rejected_before_dispatch
    Thread.current[:handler_called] = false
    handler = Ractor.shareable_proc { |_invoke| Thread.current[:handler_called] = true }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", origin: "https://evil.example"))

    refute Thread.current[:handler_called], "a foreign origin must not reach the handler"
    _id, status, headers, body = last_response
    assert_equal 200, status
    assert_equal "error", headers.to_h["Tauri-Response"]
    assert_equal '"Command ping not allowed by ACL"', body
  ensure
    StubNative.clear_event
  end

  def test_plugin_command_from_foreign_origin_is_rejected_with_full_name
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "plugin:image|new", origin: "tokra://other-host"))

    assert_equal '"Command plugin:image|new not allowed by ACL"', last_response[3]
  ensure
    StubNative.clear_event
  end

  def test_windows_origin_is_local_only_on_windows
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "missing", origin: "http://tokra.localhost"))
    assert_equal '"Command missing not allowed by ACL"', last_response[3],
      "http://tokra.localhost is foreign off Windows"

    app = Tokra::Builder.default.build(native: StubNative)
    app.stub(:os_name, "windows") do
      run_with(app, ipc_request(app, cmd: "missing", origin: "http://tokra.localhost"))
    end
    assert_equal '"Command missing not found"', last_response[3],
      "WebView2 serves the app from http://tokra.localhost"
  ensure
    StubNative.clear_event
  end

  def test_handler_exception_rejects_and_logs
    handler = Ractor.shareable_proc { |_invoke| raise ArgumentError, "boom" }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    _out, err = capture_subprocess_io do
      run_with(app, ipc_request(app, cmd: "explode"))
    end

    _id, status, headers, body = last_response
    assert_equal 200, status
    assert_equal "error", headers.to_h["Tauri-Response"], "a raising handler rejects the invoke"
    assert_equal '"boom"', body
    assert_match(/command explode failed: ArgumentError: boom/, err)
  ensure
    StubNative.clear_event
  end

  def test_handler_exception_after_resolve_keeps_the_resolution
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("done")
      raise "late"
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    capture_subprocess_io { run_with(app, ipc_request(app, cmd: "late")) }

    assert_equal 1, StubNative.responses.size, "the request is answered exactly once"
    assert_equal '"done"', last_response[3]
  ensure
    StubNative.clear_event
  end

  def test_unserializable_value_rejects_instead_of_hanging
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve("\xFF".b)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "bytes"))

    _id, status, headers, body = last_response
    assert_equal 200, status
    assert_equal "error", headers.to_h["Tauri-Response"]
    assert_kind_of String, JSON.parse(body), "the serializer message is the rejection"
  ensure
    StubNative.clear_event
  end

  def test_plugin_command_takes_only_the_second_token
    Thread.current[:command] = nil
    plugin = Class.new(Tokra::Plugin) do
      def name = "multi"

      def extend_api(invoke)
        Thread.current[:command] = invoke.command
        invoke.resolve(nil)
        true
      end
    end
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(plugin.new(app.handle))
    run_with(app, ipc_request(app, cmd: "plugin:multi|b|c", uri: "ipc://localhost/plugin%3Amulti%7Cb%7Cc"))

    assert_equal "b", Thread.current[:command], "webview/mod.rs takes tokens.next() once"
  ensure
    StubNative.clear_event
  end

  # Tauri decodes the path with percent_decode and decode_utf8_lossy, which
  # never fail; a malformed path must still produce a reply.
  def test_command_path_decoding_is_lossy_not_fatal
    Thread.current[:command] = nil
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:command] = invoke.command
      invoke.resolve(nil)
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "x", uri: "ipc://localhost/a%ZZb%FF?q=1"))

    assert_equal "a%ZZb\uFFFD", Thread.current[:command]
    assert_equal 200, last_response[1]
  ensure
    StubNative.clear_event
  end

  # wry reverts WebView2's http://ipc.localhost/ before the handler runs,
  # so that form never reaches Ruby and is not an ipc:// request.
  def test_http_ipc_localhost_is_not_the_ipc_transport
    app = Tokra::Builder.default.build(native: StubNative)
    run_with(app, ipc_request(app, cmd: "ping", uri: "http://ipc.localhost/ping"))

    assert_empty StubNative.responses, "only ipc:// URIs are invokes"
  ensure
    StubNative.clear_event
  end

  private def webview_evals(app)
    app.handle.webviews["main"].native.evals
  end
end
