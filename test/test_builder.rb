# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Mock native components for testing App without creating real windows.
# Uses the mockist approach: verify collaboration by injecting dependencies.
module MockNative
  # Simple spy that records method calls
  class Spy
    attr_reader :calls

    def initialize
      @calls = []
    end

    def method_missing(name, *, &)
      @calls << [name, *]
      self
    end

    def respond_to_missing?(*, &) = true
  end

  # Mock EventLoop that returns immediately without blocking
  class EventLoop < Spy
    def create_proxy = Proxy.new
    def run(_callback) = nil # Don't block, just return
  end

  # Mock Proxy
  class Proxy < Spy
    def respond(_id, _status, _headers, _body) = nil
  end

  # Mock Window
  class Window < Spy
    def initialize(_event_loop) = super()
    def set_title(_title) = nil
    def set_size(_width, _height) = nil
  end

  # Mock WebView factory
  module WebView
    def self.new_with_protocol(_window, _proxy) = Spy.new
  end
end

# Mock native with configurable event injection for dispatch testing
module EventNative
  @event = nil
  class << self
    attr_accessor :event
  end

  class EventLoop < MockNative::Spy
    def create_proxy = MockNative::Proxy.new

    def run(callback)
      callback.call(EventNative.event) if EventNative.event
    end
  end

  Proxy = MockNative::Proxy
  Window = MockNative::Window
  WebView = MockNative::WebView
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
      .build(native: MockNative)

    assert_instance_of Tokra::App, app
  end

  # --- Build/Run ---

  def test_build_returns_app_instance
    builder = Tokra::Builder.default
    app = builder.build(native: MockNative)
    assert_instance_of Tokra::App, app
  end

  def test_build_creates_new_app_each_time
    builder = Tokra::Builder.default
    app1 = builder.build(native: MockNative)
    app2 = builder.build(native: MockNative)
    refute_same app1, app2
  end

  def test_run_invokes_callback_with_lifecycle_events
    events = []
    Tokra::Builder.default.run(native: MockNative) do |handle, event|
      events << [handle.class, event.class]
    end
    assert_equal [
      [Tokra::AppHandle, Tokra::RunEvent::Ready],
      [Tokra::AppHandle, Tokra::RunEvent::Exit],
    ], events
  end

  # --- Callback Storage (Mutation Resistance) ---
  # These tests use spies to verify callbacks are actually stored and invocable.
  # Without these, a mutation removing the assignment would go undetected.

  def test_invoke_handler_stores_callable_block
    called_with = nil
    builder = Tokra::Builder.default.invoke_handler { |invoke| called_with = invoke }

    handler = builder.invoke_handler_hook
    refute_nil handler, "invoke_handler block should be stored"

    handler.call(:test_invoke)
    assert_equal :test_invoke, called_with
  end

  def test_register_uri_scheme_protocol_stores_by_scheme_name
    builder = Tokra::Builder.default
      .register_uri_scheme_protocol("foo") { :foo_response }
      .register_uri_scheme_protocol("bar") { :bar_response }

    protocols = builder.uri_scheme_protocols
    assert_equal 2, protocols.size
    assert_equal :foo_response, protocols["foo"].call
    assert_equal :bar_response, protocols["bar"].call
  end

  def test_setup_stores_callable_block
    called_with = nil
    builder = Tokra::Builder.default.setup { |app| called_with = app }

    setup = builder.setup_hook
    refute_nil setup
    setup.call(:test_app)
    assert_equal :test_app, called_with
  end

  def test_on_page_load_stores_callable_block
    called_with = nil
    builder = Tokra::Builder.default.on_page_load { |wv, pl| called_with = [wv, pl] }

    on_page_load = builder.on_page_load_hook
    refute_nil on_page_load
    on_page_load.call(:webview, :payload)
    assert_equal [:webview, :payload], called_with
  end

  def test_on_window_event_accumulates_multiple_handlers
    calls = []
    builder = Tokra::Builder.default
      .on_window_event { |w, e| calls << [:first, w, e] }
      .on_window_event { |w, e| calls << [:second, w, e] }

    listeners = builder.window_event_listeners
    assert_equal 2, listeners.size

    listeners.each { |l| l.call(:win, :evt) }
    assert_equal [[:first, :win, :evt], [:second, :win, :evt]], calls
  end

  # --- Setup Hook Integration ---
  # Verifies that Builder#setup hook is called when App#run executes.

  def test_setup_hook_is_called_when_app_runs
    setup_called_with = nil

    Tokra::Builder.default
      .setup { |app| setup_called_with = app }
      .run(native: MockNative)

    assert_instance_of Tokra::App, setup_called_with
  end

  def test_setup_hook_is_called_before_ready_event
    order = []

    Tokra::Builder.default
      .setup { |_app| order << :setup }
      .run(native: MockNative) { |_handle, event|
        order << :ready if event.is_a?(Tokra::RunEvent::Ready)
      }

    assert_equal [:setup, :ready], order
  end

  # --- Event Dispatch (Mutation Resistance for App#dispatch_* methods) ---
  # These tests inject events via EventNative.event to verify callbacks are invoked.

  def test_uri_scheme_protocol_handler_receives_http_request_event
    received = nil
    mock_event = MockNative::Spy.new
    mock_event.define_singleton_method(:request_id) { 42 }
    mock_event.define_singleton_method(:is_a?) { |klass|
      klass == Tokra::Native::HttpRequestEvent
    }

    EventNative.event = mock_event

    Tokra::Builder.default
      .register_uri_scheme_protocol("tokra") { |ctx, event|
        received = [ctx.class, event]
        Tokra::Response.ok("handled")
      }
      .run(native: EventNative)

    refute_nil received, "Protocol handler should have been called"
    assert_equal Tokra::UriSchemeContext, received[0]
  ensure
    EventNative.event = nil
  end

  def test_invoke_handler_receives_ipc_event
    received_payload = nil

    mock_ipc = Object.new
    mock_ipc.define_singleton_method(:message) { "test_payload" }
    mock_ipc.define_singleton_method(:is_a?) { |klass|
      klass == Tokra::Native::IpcEvent
    }

    EventNative.event = mock_ipc

    Tokra::Builder.default
      .invoke_handler { |invoke|
        received_payload = invoke.payload
        true
      }
      .run(native: EventNative)

    assert_equal "test_payload", received_payload
  ensure
    EventNative.event = nil
  end

  def test_on_page_load_receives_page_load_event
    received = nil

    mock_page_load = Object.new
    mock_page_load.define_singleton_method(:url) { "tokra://localhost/test" }
    mock_page_load.define_singleton_method(:started?) { true }
    mock_page_load.define_singleton_method(:is_a?) { |klass|
      klass == Tokra::Native::PageLoadEvent
    }

    EventNative.event = mock_page_load

    Tokra::Builder.default
      .on_page_load { |webview, payload|
        received = payload
      }
      .run(native: EventNative)

    refute_nil received
    assert_equal "tokra://localhost/test", received.url
    assert received.started?
  ensure
    EventNative.event = nil
  end

  def test_on_window_event_receives_close_event
    received_events = []

    mock_close = Object.new
    mock_close.define_singleton_method(:is_a?) { |klass|
      klass == Tokra::Native::WindowCloseEvent
    }

    EventNative.event = mock_close

    Tokra::Builder.default
      .on_window_event { |window, event|
        received_events << event.class
      }
      .run(native: EventNative)

    assert_includes received_events, Tokra::WindowEvent::CloseRequested
  ensure
    EventNative.event = nil
  end
end
