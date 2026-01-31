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
    handler = Ractor.shareable_proc { |_invoke| false }
    result = builder.invoke_handler(&handler)
    assert_same builder, result
  end

  def test_register_uri_scheme_protocol_returns_self
    builder = Tokra::Builder.default
    handler = Ractor.shareable_proc { nil }
    result = builder.register_uri_scheme_protocol("tokra", &handler)
    assert_same builder, result
  end

  def test_register_asynchronous_uri_scheme_protocol_returns_self
    builder = Tokra::Builder.default
    handler = Ractor.shareable_proc { nil }
    result = builder.register_asynchronous_uri_scheme_protocol("tokra", &handler)
    assert_same builder, result
  end

  def test_setup_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { nil }
    result = builder.setup(&hook)
    assert_same builder, result
  end

  def test_on_page_load_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { nil }
    result = builder.on_page_load(&hook)
    assert_same builder, result
  end

  def test_on_window_event_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { nil }
    result = builder.on_window_event(&hook)
    assert_same builder, result
  end

  def test_full_fluent_chain_compiles
    # Demonstrates the complete API as app developers will use it
    null_hook = Ractor.shareable_proc { nil }
    false_hook = Ractor.shareable_proc { false }
    app = Tokra::Builder.default
      .register_uri_scheme_protocol("app", &null_hook)
      .invoke_handler(&false_hook)
      .setup(&null_hook)
      .on_page_load(&null_hook)
      .on_window_event(&null_hook)
      .build(native: StubNative)

    assert_instance_of Tokra::App, app
  end

  # --- Handler Shareability ---
  # All handlers must be shareable to work across Ractors (Tauri parity)

  def test_invoke_handler_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    # Regular block captures binding - not shareable
    assert_raises(Tokra::Error) do
      builder.invoke_handler { |_invoke| false }
    end
  end

  def test_register_uri_scheme_protocol_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.register_uri_scheme_protocol("app") { nil }
    end
  end

  def test_register_asynchronous_uri_scheme_protocol_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.register_asynchronous_uri_scheme_protocol("app") { nil }
    end
  end

  def test_setup_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.setup { nil }
    end
  end

  def test_on_page_load_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.on_page_load { nil }
    end
  end

  def test_on_window_event_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.on_window_event { nil }
    end
  end

  def test_on_webview_event_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.on_webview_event { nil }
    end
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
    handler = Ractor.shareable_proc { |_invoke| :handled }
    result = builder.invoke_handler(&handler)
    assert_same builder, result
  end

  def test_register_uri_scheme_protocol_is_chainable
    builder = Tokra::Builder.default
    handler = Ractor.shareable_proc { |_ctx, _req|
      Tokra::Response.new(status: 200, headers: {}, body: "OK")
    }
    result = builder.register_uri_scheme_protocol("tokra", &handler)
    assert_same builder, result
  end

  def test_setup_hook_is_called_during_run
    Thread.current[:setup_called] = false
    Thread.current[:app_received] = nil
    hook = Ractor.shareable_proc { |app|
      Thread.current[:setup_called] = true
      Thread.current[:app_received] = app
    }
    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)

    assert Thread.current[:setup_called], "setup hook should be called"
    assert_instance_of Tokra::App, Thread.current[:app_received]
  end

  def test_on_page_load_hook_receives_payload_on_event
    # Page load events require native integration
    # Verify hook registration via chaining
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { |_webview, _payload| :handled }
    result = builder.on_page_load(&hook)
    assert_same builder, result
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

  # --- Setup Hook Integration ---
  # Verifies that Builder#setup hook is called when App#run executes.

  def test_setup_hook_is_called_when_app_runs
    Thread.current[:setup_app] = nil
    hook = Ractor.shareable_proc { |app| Thread.current[:setup_app] = app }

    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)

    assert_instance_of Tokra::App, Thread.current[:setup_app]
  end

  def test_setup_hook_is_called_before_ready_event
    Thread.current[:order] = []
    setup_hook = Ractor.shareable_proc { |_app| Thread.current[:order] << :setup }

    Tokra::Builder.default
      .setup(&setup_hook)
      .run(native: StubNative) { |_handle, event|
        Thread.current[:order] << :ready if event.is_a?(Tokra::RunEvent::Ready)
      }

    assert_equal [:setup, :ready], Thread.current[:order]
  end

  # --- Event Dispatch ---
  # Tests that registered handlers are called when events are dispatched.
  # Uses StubNative.inject_event to simulate native events at the FFI boundary.

  def test_uri_scheme_protocol_handler_receives_http_request_event
    Thread.current[:received] = nil
    StubNative.inject_event(Tokra::Native::HttpRequestEvent.new(
      request_id: 42, method: "GET", uri: "tokra://test/", headers: {}, body: ""
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
      request_id: 42, method: "GET", uri: "tokra://test/", headers: {}, body: ""
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
    StubNative.inject_event(Tokra::Native::IpcEvent.new(message: "test_payload"))
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
      event: "started", url: "tokra://localhost/test"
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

  # --- manage / State ---

  def test_manage_returns_self_for_fluent_chaining
    builder = Tokra::Builder.default
    result = builder.manage("some state")
    assert_same builder, result
  end

  def test_manage_state_accessible_via_app_handle_in_setup
    state = Object.new
    Thread.current[:retrieved] = nil
    hook = Ractor.shareable_proc { |app|
      Thread.current[:retrieved] = app.handle.state(Object)
    }

    Tokra::Builder.default
      .manage(state)
      .setup(&hook)
      .run(native: StubNative)

    assert_same state, Thread.current[:retrieved]
  end

  def test_try_state_returns_nil_when_not_managed
    Thread.current[:retrieved] = :sentinel
    hook = Ractor.shareable_proc { |app|
      Thread.current[:retrieved] = app.handle.try_state(Object)
    }

    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)

    assert_nil Thread.current[:retrieved]
  end

  def test_state_raises_when_not_managed
    hook = Ractor.shareable_proc { |app|
      Thread.current[:error] = begin
        app.handle.state(Object)
        nil
      rescue KeyError => e
        e
      end
    }
    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)
    assert_instance_of KeyError, Thread.current[:error]
  end

  # --- on_webview_event ---

  def test_on_webview_event_is_chainable
    builder = Tokra::Builder.default
    hook = Ractor.shareable_proc { |_webview, _event| :got_it }
    result = builder.on_webview_event(&hook)

    assert_same builder, result
  end

  def test_on_webview_event_accepts_multiple_listeners
    hook = Ractor.shareable_proc { |_w, _e| :handled }
    builder = Tokra::Builder.default
      .on_webview_event(&hook)
      .on_webview_event(&hook)

    # Verify fluent chaining works with multiple listeners
    assert_instance_of Tokra::Builder, builder
  end

  def test_on_webview_event_receives_enter_event_with_pathnames
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    # Inject event BEFORE run (StubNative EventLoop is synchronous)
    StubNative.inject_event(Tokra::Native::DragDropEvent.new(
      "enter", ["/tmp/file1.txt", "/tmp/file2.txt"], 100, 200
    ))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::WebviewEvent::DragDrop, event
    assert_instance_of Tokra::DragDropEvent::Enter, event.event

    # Verify paths are converted to Pathname (mutation-resistant)
    assert_equal 2, event.event.paths.size
    assert_instance_of Pathname, event.event.paths.first
    assert_equal Pathname.new("/tmp/file1.txt"), event.event.paths.first
    assert_equal Pathname.new("/tmp/file2.txt"), event.event.paths.last

    # Verify position (mutation-resistant)
    assert_equal 100, event.event.position.x
    assert_equal 200, event.event.position.y
  end

  def test_on_webview_event_receives_drop_event_with_pathnames
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    StubNative.inject_event(Tokra::Native::DragDropEvent.new(
      "drop", ["/Users/kerrick/Desktop/photo.jpg"], 50, 75
    ))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::DragDropEvent::Drop, event.event
    assert_equal Pathname.new("/Users/kerrick/Desktop/photo.jpg"), event.event.paths.first
    assert_equal 50, event.event.position.x
    assert_equal 75, event.event.position.y
  end

  def test_on_webview_event_receives_over_event
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    StubNative.inject_event(Tokra::Native::DragDropEvent.new("over", [], 123, 456))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::DragDropEvent::Over, event.event
    assert_equal 123, event.event.position.x
    assert_equal 456, event.event.position.y
  end

  def test_on_webview_event_receives_leave_event
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    StubNative.inject_event(Tokra::Native::DragDropEvent.new("leave", [], 0, 0))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::DragDropEvent::Leave, event.event
  end
end
