# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Ipc::Invoke type.
class TestInvoke < Minitest::Test
  private def stub_webview
    Tokra::Webview.new(label: "test", native: Object.new, window: Object.new, app_handle: Object.new)
  end

  def test_stores_command_and_payload
    payload = { "name" => "World" }
    invoke = Tokra::Ipc::Invoke.new(command: "greet", payload:, responder: nil, webview: stub_webview)

    assert_equal "greet", invoke.command
    assert_equal({ "name" => "World" }, invoke.payload)
  end

  def test_payload_uses_string_keys
    payload = { "text" => "Hello", "count" => 42 }
    invoke = Tokra::Ipc::Invoke.new(command: "cmd", payload:, responder: nil, webview: stub_webview)

    # String keys match serde_json::Value semantics
    assert_equal "Hello", invoke.payload["text"]
    assert_equal 42, invoke.payload["count"]
  end

  def test_resolve_calls_responder_with_success
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Ipc::Invoke.new(command: "cmd", payload: {}, responder:, webview: stub_webview)
    invoke.resolve("result")

    assert_equal [[true, "result"]], calls
  end

  def test_reject_calls_responder_with_failure
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Ipc::Invoke.new(command: "cmd", payload: {}, responder:, webview: stub_webview)
    invoke.reject("error message")

    assert_equal [[false, "error message"]], calls
  end

  def test_only_responds_once
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Ipc::Invoke.new(command: "cmd", payload: {}, responder:, webview: stub_webview)
    invoke.resolve("first")
    invoke.resolve("second")
    invoke.reject("third")

    assert_equal 1, calls.size, "Should only call responder once"
    assert_equal [[true, "first"]], calls
  end

  def test_without_responder_does_not_error
    invoke = Tokra::Ipc::Invoke.new(command: "cmd", payload: {}, responder: nil, webview: stub_webview)

    # Should not raise
    invoke.resolve("value")
    invoke.reject("error")
  end

  def test_webview_accessor_returns_webview
    webview = stub_webview
    invoke = Tokra::Ipc::Invoke.new(command: "cmd", payload: {}, responder: nil, webview:)

    assert_same webview, invoke.webview
  end
end
