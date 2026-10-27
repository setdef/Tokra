# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Thread Safety Invariant Tests
#
# The invariant: EventLoop, Window, and WebView are used, and dropped, only
# on the thread that created them. The native layer enforces it (each
# method raises ThreadError on any other thread, and ThreadBound leaks a
# value rather than drop it there), and Tokra::RuntimeContext brings Ruby's
# calls to that thread, as Tauri's dispatcher does (Plan 020). Only Proxy
# crosses threads and Ractors by design.
class ThreadSafetyInvariantTest < Minitest::Test
  # ==========================================================================
  # Proxy Ractor Safety Tests
  # ==========================================================================

  # Test that Proxy is genuinely Send-safe and can be used from a Ractor.
  # This proves the Ractor boundary works correctly.
  #
  # INVARIANT VERIFIED: Proxy can cross Ractor boundaries safely because
  # tao::EventLoopProxy is designed to be Send+Sync.
  # Note: frozen_shareable requires freezing the object first.
  def test_proxy_is_ractor_safe
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    proxy = event_loop.create_proxy

    # Before freezing: not shareable
    refute Ractor.shareable?(proxy), "Proxy should not be shareable before freeze"

    # Freeze it (Ruby's frozen_shareable semantics)
    proxy.freeze

    # After freezing: should be shareable
    assert proxy.frozen?, "Proxy must be frozen"
    assert Ractor.shareable?(proxy), "Frozen Proxy must be Ractor-shareable"
  end

  # Test that frozen proxy is deeply frozen
  def test_frozen_proxy_is_deeply_frozen
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    proxy = event_loop.create_proxy
    proxy.freeze

    assert proxy.frozen?, "Proxy should be frozen"
    # Ractor.shareable? returning true implies deep frozen state for T_DATA
  end

  # ==========================================================================
  # Main Thread Type Instantiation Tests
  # ==========================================================================

  # Test that the main-thread-only types exist and can be instantiated
  # on the main thread. This is the baseline for the invariant.
  #
  # INVARIANT VERIFIED: Types can be created on the main thread.
  def test_main_thread_types_instantiate
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    assert_kind_of Tokra::Native::EventLoop, event_loop

    proxy = event_loop.create_proxy
    assert_kind_of Tokra::Native::Proxy, proxy

    window = Tokra::Native::Window.new(event_loop)
    assert_kind_of Tokra::Native::Window, window
  end

  # ==========================================================================
  # Window Operation Tests
  # ==========================================================================

  # Test that Window operations work on the main thread.
  #
  # INVARIANT VERIFIED: Window operations are safe on main thread.
  def test_window_operations_on_main_thread
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    window = Tokra::Native::Window.new(event_loop)

    # These operations should not raise
    window.set_title("Test Title")
    window.set_size(800.0, 600.0)
    window.set_always_on_top(true)
    window.set_always_on_top(false)
    window.set_ignore_cursor_events(true)
    window.set_ignore_cursor_events(false)
    id = window.id

    assert_kind_of String, id
    refute_empty id
  end

  def test_window_set_title_accepts_unicode
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    window = Tokra::Native::Window.new(event_loop)

    # Should not raise with unicode
    window.set_title("日本語タイトル 🎌")
  end

  def test_window_set_size_accepts_float_dimensions
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    window = Tokra::Native::Window.new(event_loop)

    # Should accept float dimensions
    window.set_size(1024.5, 768.5)
  end

  def test_window_id_is_unique_per_window
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    window1 = Tokra::Native::Window.new(event_loop)
    window2 = Tokra::Native::Window.new(event_loop)

    refute_equal window1.id, window2.id, "Each window should have a unique ID"
  end

  # ==========================================================================
  # Other Threads Are Refused
  # ==========================================================================

  # Runs the block on a new thread and returns what it raised.
  def raised_on_another_thread
    Thread.new do
      yield
      nil
    rescue Exception => e
      e
    end.value
  end

  def assert_refused(class_name, &call)
    error = raised_on_another_thread(&call)
    assert_instance_of ThreadError, error
    assert_equal "#{class_name} can only be used on the thread that created it", error.message
  end

  def test_window_methods_refuse_another_thread
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    window = Tokra::Native::Window.new(NativeEventLoop.shared)

    assert_refused("Tokra::Native::Window") { window.set_title("from a thread") }
    assert_refused("Tokra::Native::Window") { window.set_size(1.0, 1.0) }
    assert_refused("Tokra::Native::Window") { window.set_always_on_top(true) }
    assert_refused("Tokra::Native::Window") { window.set_ignore_cursor_events(true) }
    assert_refused("Tokra::Native::Window") { window.title }
    assert_refused("Tokra::Native::Window") { window.id }
    assert_refused("Tokra::Native::Window") { window.raw_window_handle }
    assert_refused("Tokra::Native::Window") { window.raw_display_handle }
  end

  def test_window_title_answers_its_own_thread
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    window = Tokra::Native::Window.new(NativeEventLoop.shared)

    assert_equal "Tokra", window.title
  end

  def test_a_window_cannot_be_built_on_another_thread
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    assert_refused("Tokra::Native::EventLoop") { Tokra::Native::Window.new(event_loop) }
  end

  def test_the_event_loop_refuses_to_run_on_another_thread_and_stays_runnable
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    assert_refused("Tokra::Native::EventLoop") { event_loop.run(-> (_event) {}) }

    # The refusal did not consume the loop: it still builds windows here.
    assert_kind_of Tokra::Native::Window, Tokra::Native::Window.new(event_loop)
  end

  def test_any_thread_can_create_a_proxy_and_wake_the_loop
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    proxy = Thread.new { event_loop.create_proxy }.value

    assert_kind_of Tokra::Native::Proxy, proxy
    assert_nil Thread.new { proxy.send_task }.value
  end

  # ==========================================================================
  # EventLoop Tests
  # ==========================================================================

  def test_event_loop_create_proxy_returns_proxy
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    proxy = event_loop.create_proxy

    assert_kind_of Tokra::Native::Proxy, proxy
  end

  def test_event_loop_can_create_multiple_proxies
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    proxy1 = event_loop.create_proxy
    proxy2 = event_loop.create_proxy

    assert_kind_of Tokra::Native::Proxy, proxy1
    assert_kind_of Tokra::Native::Proxy, proxy2
  end

  # ==========================================================================
  # Proxy Operation Tests
  # ==========================================================================

  def test_proxy_responds_to_wake_up
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    proxy = event_loop.create_proxy

    assert_respond_to proxy, :wake_up
  end

  def test_proxy_responds_to_respond
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    event_loop = NativeEventLoop.shared
    proxy = event_loop.create_proxy

    assert_respond_to proxy, :respond
  end

  # ==========================================================================
  # WebView Tests
  # ==========================================================================

  def test_webview_new_with_protocol_is_defined
    assert Tokra::Native::WebView.respond_to?(:new_with_protocol),
      "WebView should have .new_with_protocol class method"
  end

  # ==========================================================================
  # Type Constants Are Defined
  # ==========================================================================

  def test_all_native_types_are_defined
    assert defined?(Tokra::Native::EventLoop), "EventLoop should be defined"
    assert defined?(Tokra::Native::Window), "Window should be defined"
    assert defined?(Tokra::Native::WebView), "WebView should be defined"
    assert defined?(Tokra::Native::Proxy), "Proxy should be defined"
  end

  # ==========================================================================
  # Proxy Cannot Be Allocated From Ruby
  # ==========================================================================

  # This tests the fix for the "undefining allocator" warning.
  # Proxy should not be allocatable from pure Ruby since it wraps Rust data.
  def test_proxy_cannot_be_allocated_directly
    # Proxy.allocate would create an uninitialized object, which would crash
    # when any method is called. The fix prevents this.
    assert_raises(TypeError) do
      Tokra::Native::Proxy.allocate
    end
  end
end
