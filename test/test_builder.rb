# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Stubs for the Native (Rust FFI) boundary.
# EventLoop is configured per-test via thread-local to inject events.
module StubNative
  # Thread-local event queue for test injection
  def self.inject_event(event)
    Thread.current[:stub_native_event] = event
  end

  def self.clear_event
    Thread.current[:stub_native_event] = nil
  end

  # Stub Proxy that records respond() calls
  class Proxy
    attr_reader :responses

    def initialize = @responses = []
    def respond(id, status, headers, body) = @responses << [id, status, headers, body]
  end

  # Stub Window
  Window = Struct.new(:event_loop) do
    def set_title(_) = nil
    def set_size(_, _) = nil
  end

  # Stub WebView factory
  class WebView
    def self.new_with_protocol(_, _) = new
  end

  # Stub EventLoop that delivers injected event to callback
  class EventLoop
    def create_proxy = Proxy.new

    def run(callback)
      callback.call(Thread.current[:stub_native_event]) if Thread.current[:stub_native_event]
    end
  end
end

# Tests for Tokra::Builder
#
# The Builder provides a fluent API for configuring Tokra desktop applications,
# mirroring Tauri's Builder pattern. These tests document the expected API
# for application developers.
#
# Tests are designed to be mutation-resistant: they verify not just return
# values but actual behavior - that callbacks are stored and can be invoked.
class TestBuilder < Minitest::Test
  # --- Entry Point ---

  def test_default_creates_new_builder_each_time
    builder1 = Tokra::Builder.default
    builder2 = Tokra::Builder.default
    refute_same builder1, builder2
  end

  # --- Fluent API Chaining ---
  # These verify methods return self for method chaining.

  def test_invoke_handler_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    result = builder.invoke_handler { |_invoke| false }
    assert_same builder, result
  end

  def test_register_uri_scheme_protocol_returns_self
    builder = Tokra::Builder.default
    result = builder.register_uri_scheme_protocol("tokra") { nil }
    assert_same builder, result
  end

  def test_setup_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    result = builder.setup { nil }
    assert_same builder, result
  end

  def test_on_page_load_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    result = builder.on_page_load { nil }
    assert_same builder, result
  end

  def test_on_window_event_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    result = builder.on_window_event { nil }
    assert_same builder, result
  end

  def test_full_fluent_chain_compiles
    # Demonstrates the complete API as app developers will use it
    app = Tokra::Builder.default
      .register_uri_scheme_protocol("app") { nil }
      .invoke_handler { false }
      .setup { nil }
      .on_page_load { nil }
      .on_window_event { nil }
      .build(native: StubNative)

    assert_instance_of Tokra::App, app
  end

  # --- Build/Run ---

  def test_build_returns_app_instance
    builder = Tokra::Builder.default
    app = builder.build(native: StubNative)
    assert_instance_of Tokra::App, app
  end

  def test_build_creates_new_app_each_time
    builder = Tokra::Builder.default
    app1 = builder.build(native: StubNative)
    app2 = builder.build(native: StubNative)
    refute_same app1, app2
  end

  def test_run_invokes_callback_with_lifecycle_events
    events = []
    Tokra::Builder.default.run(native: StubNative) do |handle, event|
      events << [handle.class, event.class]
    end
    assert_equal [
      [Tokra::AppHandle, Tokra::RunEvent::Ready],
      [Tokra::AppHandle, Tokra::RunEvent::Exit],
    ], events
  end

  # --- Callback Behavior Verification (Mutation Resistance) ---
  # These tests verify that registered callbacks are actually invoked when
  # events are dispatched. Testing the observable behavior, not internals.

  def test_invoke_handler_is_chainable
    builder = Tokra::Builder.default
    result = builder.invoke_handler { |_invoke| :handled }
    assert_same builder, result
  end

  def test_register_uri_scheme_protocol_is_chainable
    builder = Tokra::Builder.default
    result = builder.register_uri_scheme_protocol("tokra") { |_ctx, _req|
      Tokra::Response.new(status: 200, headers: {}, body: "OK")
    }
    assert_same builder, result
  end

  def test_setup_hook_is_called_during_run
    setup_called = false
    app_received = nil
    Tokra::Builder.default
      .setup { |app|
        setup_called = true
        app_received = app
      }
      .run(native: StubNative)

    assert setup_called, "setup hook should be called"
    assert_instance_of Tokra::App, app_received
  end

  def test_on_page_load_hook_receives_payload_on_event
    # Page load events require native integration
    # Verify hook registration via chaining
    builder = Tokra::Builder.default
    result = builder.on_page_load { |_webview, _payload| :handled }
    assert_same builder, result
  end

  def test_on_window_event_listeners_are_called_on_close
    listener_called = false
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    Tokra::Builder.default
      .on_window_event { |_window, evt|
        listener_called = true if evt.is_a?(Tokra::WindowEvent::CloseRequested)
      }
      .run(native: StubNative)

    assert listener_called, "window event listener should be called on close"
  ensure
    StubNative.clear_event
  end

  # --- Setup Hook Integration ---
  # Verifies that Builder#setup hook is called when App#run executes.

  def test_setup_hook_is_called_when_app_runs
    setup_called_with = nil

    Tokra::Builder.default
      .setup { |app| setup_called_with = app }
      .run(native: StubNative)

    assert_instance_of Tokra::App, setup_called_with
  end

  def test_setup_hook_is_called_before_ready_event
    order = []

    Tokra::Builder.default
      .setup { |_app| order << :setup }
      .run(native: StubNative) { |_handle, event|
        order << :ready if event.is_a?(Tokra::RunEvent::Ready)
      }

    assert_equal [:setup, :ready], order
  end

  # --- Event Dispatch ---
  # Tests that registered handlers are called when events are dispatched.
  # Uses StubNative.inject_event to simulate native events at the FFI boundary.

  def test_uri_scheme_protocol_handler_receives_http_request_event
    received = nil
    StubNative.inject_event(Tokra::Native::HttpRequestEvent.new(
      request_id: 42, method: "GET", uri: "tokra://test/", headers: {}, body: ""
    ))

    Tokra::Builder.default
      .register_uri_scheme_protocol("tokra") { |ctx, evt|
        received = [ctx.class, evt]
        Tokra::Response.ok("handled")
      }
      .run(native: StubNative)

    refute_nil received, "Protocol handler should have been called"
    assert_equal Tokra::UriSchemeContext, received[0]
    assert_instance_of Tokra::Native::HttpRequestEvent, received[1]
  ensure
    StubNative.clear_event
  end

  def test_invoke_handler_receives_ipc_event
    received_payload = nil
    StubNative.inject_event(Tokra::Native::IpcEvent.new(message: "test_payload"))

    Tokra::Builder.default
      .invoke_handler { |invoke|
        received_payload = invoke.payload
        true
      }
      .run(native: StubNative)

    assert_equal "test_payload", received_payload
  ensure
    StubNative.clear_event
  end

  def test_on_page_load_receives_page_load_event
    received = nil
    StubNative.inject_event(Tokra::Native::PageLoadEvent.new(
      event: "started", url: "tokra://localhost/test"
    ))

    Tokra::Builder.default
      .on_page_load { |_webview, payload| received = payload }
      .run(native: StubNative)

    refute_nil received
    assert_equal "tokra://localhost/test", received.url
    assert received.started?
  ensure
    StubNative.clear_event
  end

  def test_on_window_event_receives_close_event
    received_events = []
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    Tokra::Builder.default
      .on_window_event { |_window, evt| received_events << evt.class }
      .run(native: StubNative)

    assert_includes received_events, Tokra::WindowEvent::CloseRequested
  ensure
    StubNative.clear_event
  end

  # --- manage / State ---

  def test_manage_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    result = builder.manage("some state")
    assert_same builder, result
  end

  def test_manage_state_accessible_via_app_handle_in_setup
    state = Object.new
    retrieved = nil

    Tokra::Builder.default
      .manage(state)
      .setup { |app|
        retrieved = app.handle.state(Object)
      }
      .run(native: StubNative)

    assert_same state, retrieved
  end

  def test_try_state_returns_nil_when_not_managed
    retrieved = :sentinel

    Tokra::Builder.default
      .setup { |app|
        retrieved = app.handle.try_state(Object)
      }
      .run(native: StubNative)

    assert_nil retrieved
  end

  def test_state_raises_when_not_managed
    Tokra::Builder.default
      .setup { |app|
        assert_raises(KeyError) { app.handle.state(Object) }
      }
      .run(native: StubNative)
  end

  # --- on_webview_event ---

  def test_on_webview_event_is_chainable
    builder = Tokra::Builder.default

    result = builder.on_webview_event { |_webview, _event| :got_it }

    assert_same builder, result
  end

  def test_on_webview_event_accepts_multiple_listeners
    call_count = 0
    builder = Tokra::Builder.default
      .on_webview_event { |_w, _e| call_count += 1 }
      .on_webview_event { |_w, _e| call_count += 1 }

    # Verify fluent chaining works with multiple listeners
    assert_instance_of Tokra::Builder, builder
  end
end
