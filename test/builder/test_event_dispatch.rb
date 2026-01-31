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

  def test_invoke_handler_receives_ipc_event
    Thread.current[:test_payload] = nil
    StubNative.inject_event(Tokra::Native::IpcEvent.new("test_payload"))
    handler = Ractor.shareable_proc { |invoke|
      Thread.current[:test_payload] = invoke.payload
      true
    }

    Tokra::Builder.default
      .invoke_handler(&handler)
      .run(native: StubNative)

    assert_equal "test_payload", Thread.current[:test_payload]
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
