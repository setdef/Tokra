# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/local_origin"
require_relative "../support/stub_native"

# Tests the channel-data fetch command, plugin:__TAURI_CHANNEL__|fetch,
# through App's router, and the postMessage results Tauri sends over a
# Channel (Plan 037). The fetch requests are the ones Tauri's fetch
# script makes through the real client: a JSON null body and a
# Tauri-Channel-Id header (channel.rs:178-180, ipc-protocol.js).
class TestBuilderIpcChannelFetch < Minitest::Test
  Queue = Tokra::Ipc::ChannelDataIpcQueue

  private def fetch_request(app, channel_id: nil, origin: LocalOrigin.url("", app:))
    headers = [
      ["Content-Type", "application/json"],
      ["Tauri-Callback", "100"],
      ["Tauri-Error", "200"],
      ["Tauri-Invoke-Key", app.invoke_key],
      ["Origin", origin],
    ]
    headers << ["Tauri-Channel-Id", channel_id] if channel_id
    Tokra::Native::HttpRequestEvent.new(
      request_id: 7, method: "POST", uri: "ipc://localhost/plugin%3A__TAURI_CHANNEL__%7Cfetch", headers:, body: "null"
    )
  end

  # Runs +events+ in one loop and returns each ipc:// reply as
  # [status, headers, body].
  private def run_events(app, events)
    StubNative.inject_event(events)
    app.run
    StubNative.responses.map { |(_id, status, headers, body)| [status, headers.to_h, body] }
  end

  private def ipc_message(app, message)
    Tokra::Native::IpcEvent.new(
      JSON.generate(message.merge("__TAURI_INVOKE_KEY__" => app.invoke_key)),
      LocalOrigin.url(app:)
    )
  end

  private def webview_evals(app)
    app.handle.webviews["main"].native.evals
  end

  def teardown
    StubNative.clear_event
  end

  # channel.rs:318-337: the data leaves the queue as a Response, raw bytes
  # as application/octet-stream.
  def test_fetch_answers_queued_bytes_once
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.state(Queue).insert(41, "\x00\xFF".b)

    first, second = run_events(app, [fetch_request(app, channel_id: "41"), fetch_request(app, channel_id: "41")])

    status, headers, body = first
    assert_equal [200, "ok", "application/octet-stream", "\x00\xFF".b],
      [status, headers["Tauri-Response"], headers["Content-Type"], body.b]
    _, headers, body = second
    assert_equal ["error", '"data not found"'], [headers["Tauri-Response"], body]
  end

  def test_fetch_answers_queued_json_as_json
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.state(Queue).insert(42, '{"big":true}')

    _, headers, body = run_events(app, [fetch_request(app, channel_id: "+42")]).first
    assert_equal ["ok", "application/json", '{"big":true}'], [headers["Tauri-Response"], headers["Content-Type"], body]
  end

  # A header that is missing, not visible ASCII, or not a u32 is the same
  # error, as Tauri chains the three checks with and_then.
  def test_fetch_without_a_readable_id_rejects
    app = Tokra::Builder.default.build(native: StubNative)
    ids = [nil, "x", "-1", "4294967296", "\u00e91"]
    replies = run_events(app, ids.map { |channel_id| fetch_request(app, channel_id:) })
    assert_equal [["error", '"missing channel id header"']] * ids.size,
      replies.map { |(_status, headers, body)| [headers["Tauri-Response"], body] }
  end

  # The plugin answers fetch and nothing else (channel.rs:339-345), so
  # another command is not found.
  def test_the_channel_plugin_handles_only_fetch
    app = Tokra::Builder.default.build(native: StubNative)
    event = fetch_request(app, channel_id: "1")
    event = event.with(uri: "ipc://localhost/plugin%3A__TAURI_CHANNEL__%7Cother")
    _, headers, body = run_events(app, [event]).first
    assert_equal ["error", '"Command other not found"'], [headers["Tauri-Response"], body]
  end

  # webview/mod.rs:1802-1806: the fetch command skips the ACL check, so it
  # skips the stopgap that stands in for it (ADR 010).
  def test_fetch_is_not_subject_to_the_origin_stopgap
    app = Tokra::Builder.default.build(native: StubNative)
    _, headers, body = run_events(app, [fetch_request(app, channel_id: "9999999", origin: "https://example.com")]).first
    assert_equal ["error", '"data not found"'], [headers["Tauri-Response"], body]
  end

  # ipc/protocol.rs:371-407: off macOS a postMessage object, array, or raw
  # result travels over Channel::from_callback_fn.
  def test_post_message_results_travel_over_a_channel_off_macos
    handler = Ractor.shareable_proc { |invoke|
      case invoke.command
      when "obj" then invoke.resolve({ "a" => 1 })
      when "text" then invoke.resolve("hi")
      when "long_text" then invoke.resolve("x" * 9000)
      when "bytes" then invoke.resolve(Tokra::Ipc::Response.new("\x01\x02".b))
      when "big" then invoke.resolve(Tokra::Ipc::Response.new("\x01".b * 1024))
      when "fail" then invoke.reject({ "a" => 1 })
      end
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    app.stub(:os_name, "linux") do
      run_events(app, %w[obj text bytes big fail long_text].map { |cmd| ipc_message(app, "cmd" => cmd, "callback" => 1, "error" => 2) })
    end

    evals = webview_evals(app)
    assert_equal 'window.__TAURI_INTERNALS__.runCallback(1, {"a":1})', evals[0]
    assert_equal 'window.__TAURI_INTERNALS__.runCallback(1, "hi")', evals[1]
    assert_equal "window.__TAURI_INTERNALS__.runCallback(1, new Uint8Array([1,2]).buffer)", evals[2]
    id = Integer(evals[3][/'Tauri-Channel-Id': '(\d+)'/, 1])
    assert evals[3].end_with?(".then((response) => window.__TAURI_INTERNALS__.runCallback(1, response)).catch(console.error)")
    assert_equal "\x01".b * 1024, app.handle.state(Queue).remove(id)
    assert_equal 'window.__TAURI_INTERNALS__.runCallback(2, {"a":1})', evals[4]
    # A JSON string is neither object nor array, so even past the 8 KiB
    # threshold it is evaluated, never fetched (ipc/protocol.rs:373-375).
    assert_equal %(window.__TAURI_INTERNALS__.runCallback(1, "#{'x' * 9000}")), evals[5]
  end

  # can_use_channel_for_response (ipc/protocol.rs:337-339): never for the
  # fetch command, nor when the client reports ipc:// blocked, nor on
  # macOS (390-402); these evaluate a number array.
  def test_post_message_results_are_evaluated_where_tauri_evaluates_them
    handler = Ractor.shareable_proc { |invoke|
      invoke.resolve(Tokra::Ipc::Response.new("\x01\x02".b))
      true
    }
    app = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    app.handle.state(Queue).insert(77, "\x01\x02".b)
    # Built inside the stub, so the page's origin is Windows' own.
    app.stub(:os_name, "windows") do
      run_events(app, [
        ipc_message(app, "cmd" => "bytes", "callback" => 1, "error" => 2,
          "options" => { "customProtocolIpcBlocked" => true }),
        ipc_message(app, "cmd" => "plugin:__TAURI_CHANNEL__|fetch", "callback" => 1, "error" => 2, "payload" => nil,
          "options" => { "headers" => { "Tauri-Channel-Id" => "77" } }),
      ])
    end
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(1, [1,2])"] * 2, webview_evals(app)

    mac = Tokra::Builder.default.invoke_handler(&handler).build(native: StubNative)
    mac.stub(:os_name, "macos") { run_events(mac, [ipc_message(mac, "cmd" => "bytes", "callback" => 1, "error" => 2)]) }
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(1, [1,2])"], webview_evals(mac)
  end
end
