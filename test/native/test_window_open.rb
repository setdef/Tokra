# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Native::Window.empty and #open, and Native::WebView.empty and #open,
# against the real extension (plan 052, decision b3): an empty native
# answers as a closed one, #open fills it once with the title and size it
# is given, a native that was ever open never opens again, and #discard
# drops a window whose webview failed (decision b4).
class TestNativeWindowOpen < Minitest::Test
  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
    @proxy = @event_loop.create_proxy
  end

  def test_an_empty_window_answers_as_a_closed_one_until_open_fills_it
    window = Tokra::Native::Window.empty(@proxy)
    assert_nil window.title

    assert_nil window.open(@event_loop, "open-1", "Opened", [200.0, 150.0])

    assert_equal "Opened", window.title
    width, height = window.inner_size(nil)
    scale = window.scale_factor
    assert_equal [200, 150], [(width / scale).round, (height / scale).round], "open builds the window at its size"
  ensure
    window&.close
  end

  def test_a_window_opens_once
    window = Tokra::Native::Window.empty(@proxy)
    window.open(@event_loop, "open-2", "Once", nil)

    error = assert_raises(RuntimeError) { window.open(@event_loop, "open-2b", "Twice", nil) }
    assert_equal "Window is already open", error.message
  ensure
    window&.close
  end

  def test_a_closed_window_never_opens_again
    window = Tokra::Native::Window.empty(@proxy)
    window.open(@event_loop, "open-3", "Closed", nil)
    window.close

    error = assert_raises(RuntimeError) { window.open(@event_loop, "open-3b", "Again", nil) }
    assert_equal "Window is already open", error.message
    assert_nil window.title
  end

  def test_discard_drops_the_window
    window = Tokra::Native::Window.empty(@proxy)
    window.open(@event_loop, "open-4", "Discarded", nil)

    assert_nil window.discard
    assert_nil window.title
    assert_nil window.discard, "discarding twice does nothing"
  end

  def test_a_closed_webview_never_opens_again
    window = Tokra::Native::Window.new(@event_loop, "open-5")
    webview = Tokra::Native::WebView.empty(@proxy)
    webview.open(window, @proxy, "open-5", "tokra://localhost/", [])
    webview.close

    error = assert_raises(RuntimeError) { webview.open(window, @proxy, "open-5", "tokra://localhost/", []) }
    assert_equal "WebView is already open", error.message
  ensure
    window&.close
  end
end
