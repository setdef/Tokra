# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Builder event dispatch.
# Tests that registered handlers are called when events are dispatched.
# Uses StubNative.inject_event to simulate native events at the FFI boundary.
class TestBuilderEventDispatch < Minitest::Test
  def test_uri_scheme_protocol_handler_receives_http_request_event
    Thread.current[:received] = nil
    StubNative.inject_event(Tokra::Native::HttpRequestEvent.new(
      42, "GET", "tokra://test/", {}, ""
    ))
    handler = Ractor.shareable_proc { |ctx, evt|
      Thread.current[:received] = [ctx.class, evt]
      Tokra::Response.ok("handled")
    }

    Tokra::Builder.default
      .register_uri_scheme_protocol("tokra", &handler)
      .run(native: StubNative)

    refute_nil Thread.current[:received], "Protocol handler should have been called"
    assert_equal Tokra::UriSchemeContext, Thread.current[:received][0]
    assert_instance_of Tokra::Native::HttpRequestEvent, Thread.current[:received][1]
  ensure
    StubNative.clear_event
  end

  def test_async_uri_scheme_protocol_handler_receives_responder
    Thread.current[:received] = nil
    StubNative.inject_event(Tokra::Native::HttpRequestEvent.new(
      42, "GET", "tokra://test/", {}, ""
    ))
    handler = Ractor.shareable_proc { |ctx, evt, responder|
      Thread.current[:received] = [ctx.class, evt.class, responder.class]
      responder.respond(Tokra::Response.ok("async handled"))
    }

    Tokra::Builder.default
      .register_asynchronous_uri_scheme_protocol("tokra", &handler)
      .run(native: StubNative)

    refute_nil Thread.current[:received], "Async protocol handler should have been called"
    assert_equal Tokra::UriSchemeContext, Thread.current[:received][0]
    assert_equal Tokra::Native::HttpRequestEvent, Thread.current[:received][1]
    assert_equal Tokra::UriSchemeResponder, Thread.current[:received][2]
  ensure
    StubNative.clear_event
  end

  def test_invoke_handler_receives_parsed_payload
    Thread.current[:test_invoke] = nil
    json_message = '{"cmd":"plugin:test|greet","text":"Hello"}'
    StubNative.inject_event(Tokra::Native::IpcEvent.new(json_message))
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:test_invoke] = invoke
      true
    }

    Tokra::Builder.default
      .invoke_handler(&handler)
      .run(native: StubNative)

    invoke = Thread.current[:test_invoke]
    refute_nil invoke, "Handler should have received invoke"

    # Payload should be pre-parsed Hash with String keys (matching serde_json::Value)
    assert_kind_of Hash, invoke.payload, "Payload should be parsed JSON Hash"
    assert_equal "Hello", invoke.payload["text"], "Payload should have String keys"
  ensure
    StubNative.clear_event
  end

  def test_invoke_handler_extracts_command_from_payload
    Thread.current[:test_invoke] = nil
    json_message = '{"cmd":"plugin:clipboard-manager|read_text"}'
    StubNative.inject_event(Tokra::Native::IpcEvent.new(json_message))
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:test_invoke] = invoke
      true
    }

    Tokra::Builder.default
      .invoke_handler(&handler)
      .run(native: StubNative)

    invoke = Thread.current[:test_invoke]
    refute_nil invoke, "Handler should have received invoke"

    # Command should be extracted from parsed payload "cmd" field
    assert_equal "plugin:clipboard-manager|read_text", invoke.command
  ensure
    StubNative.clear_event
  end

  def test_on_page_load_receives_page_load_event
    Thread.current[:received] = nil
    StubNative.inject_event(Tokra::Native::PageLoadEvent.new(
      "started", "tokra://localhost/test"
    ))
    hook = Ractor.shareable_proc { |_webview, payload| Thread.current[:received] = payload }

    Tokra::Builder.default
      .on_page_load(&hook)
      .run(native: StubNative)

    refute_nil Thread.current[:received]
    assert_equal "tokra://localhost/test", Thread.current[:received].url
    assert Thread.current[:received].started?
  ensure
    StubNative.clear_event
  end

  def test_on_window_event_receives_close_event
    Thread.current[:received_events] = []
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)
    hook = Ractor.shareable_proc { |_window, evt| Thread.current[:received_events] << evt.class }

    Tokra::Builder.default
      .on_window_event(&hook)
      .run(native: StubNative)

    assert_includes Thread.current[:received_events], Tokra::WindowEvent::CloseRequested
  ensure
    StubNative.clear_event
  end

  def test_on_window_event_listeners_are_called_on_close
    Thread.current[:listener_called] = false
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)
    hook = Ractor.shareable_proc { |_window, evt|
      Thread.current[:listener_called] = true if evt.is_a?(Tokra::WindowEvent::CloseRequested)
    }

    Tokra::Builder.default
      .on_window_event(&hook)
      .run(native: StubNative)

    assert Thread.current[:listener_called], "window event listener should be called on close"
  ensure
    StubNative.clear_event
  end
end
