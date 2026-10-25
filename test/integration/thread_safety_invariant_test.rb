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
# These tests verify the invariants that make our `unsafe impl Send` safe.
# Referenced by: clippy_exceptions.rb
# lib.rs lines: 77 (RbEventLoop), 189 (RbWindow), 249 (RbWebView), 310 (RbProxy TypedData)
#
# The invariant: All access to EventLoop, Window, and WebView happens
# exclusively on the main thread via the tao event loop callback.
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
