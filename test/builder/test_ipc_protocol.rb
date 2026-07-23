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
    origin: "ipc://localhost", uri: nil, omit: []
  )
    headers = [] #: Array[[String, String]]
    headers << ["Content-Type", content_type] unless omit.include?(:content_type)
    headers << ["Tauri-Callback", callback] unless omit.include?(:callback)
    headers << ["Tauri-Error", error] unless omit.include?(:error)
    invoke_key = (key == :app) ? app.invoke_key : key
    headers << ["Tauri-Invoke-Key", invoke_key] unless omit.include?(:invoke_key)
    headers << ["Origin", origin] unless omit.include?(:origin)

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

  private def webview_evals(app)
    app.handle.webviews["main"].native.evals
  end
end
