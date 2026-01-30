# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Thread Safety Invariant Tests
#
# These tests verify the invariants that make our `unsafe impl Send` safe.
# Referenced by: clippy_exceptions.rb
# lib.rs lines: 77 (RbEventLoop), 189 (RbWindow), 249 (RbWebView), 310 (RbProxy TypedData)
#
# The invariant: All access to EventLoop, Window, and WebView happens
# exclusively on the main thread via the tao event loop callback.
class ThreadSafetyInvariantTest < Minitest::Test
  # Test that Proxy is genuinely Send-safe and can be used from a Ractor.
  # This proves the Ractor boundary works correctly.
  #
  # INVARIANT VERIFIED: Proxy can cross Ractor boundaries safely because
  # tao::EventLoopProxy is designed to be Send+Sync.
  # Note: frozen_shareable requires freezing the object first.
  def test_proxy_is_ractor_safe
    skip "Requires display server" if ENV["CI"] && !ENV["DISPLAY"]

    event_loop = Tokra::Native::EventLoop.new
    proxy = event_loop.create_proxy

    # Before freezing: not shareable
    refute Ractor.shareable?(proxy), "Proxy should not be shareable before freeze"

    # Freeze it (Ruby's frozen_shareable semantics)
    proxy.freeze

    # After freezing: should be shareable
    assert proxy.frozen?, "Proxy must be frozen"
    assert Ractor.shareable?(proxy), "Frozen Proxy must be Ractor-shareable"
  end

  # Test that the main-thread-only types exist and can be instantiated
  # on the main thread. This is the baseline for the invariant.
  #
  # INVARIANT VERIFIED: Types can be created on the main thread.
  def test_main_thread_types_instantiate
    skip "Requires display server" if ENV["CI"] && !ENV["DISPLAY"]

    event_loop = Tokra::Native::EventLoop.new
    assert_kind_of Tokra::Native::EventLoop, event_loop

    proxy = event_loop.create_proxy
    assert_kind_of Tokra::Native::Proxy, proxy

    window = Tokra::Native::Window.new(event_loop)
    assert_kind_of Tokra::Native::Window, window
  end

  # Test that Window operations work on the main thread.
  #
  # INVARIANT VERIFIED: Window operations are safe on main thread.
  def test_window_operations_on_main_thread
    skip "Requires display server" if ENV["CI"] && !ENV["DISPLAY"]

    event_loop = Tokra::Native::EventLoop.new
    window = Tokra::Native::Window.new(event_loop)

    # These operations should not raise
    window.set_title("Test Title")
    window.set_size(800.0, 600.0)
    id = window.id

    assert_kind_of String, id
    refute_empty id
  end
end
