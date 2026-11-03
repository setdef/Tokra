# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# A label crosses into the native layer as UTF-8 without NUL (plan 052,
# decision 2): wry copies a webview's id into a C string with unwrap on
# macOS (wry 0.54.1 src/wkwebview/mod.rs:274-277), so a NUL would panic
# inside webview creation, which Ruby sees as fatal. The constructors
# refuse it with ArgumentError first.
class TestNativeLabels < Minitest::Test
  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
  end

  def test_a_window_label_holding_nul_is_refused_before_a_window_is_built
    error = assert_raises(ArgumentError) { Tokra::Native::Window.new(@event_loop, "ma\0in") }

    assert_equal "label contains null byte", error.message
  end

  def test_a_webview_label_holding_nul_is_refused_before_a_webview_is_built
    window = Tokra::Native::Window.new(@event_loop, "labels-window")
    error = assert_raises(ArgumentError) do
      Tokra::Native::WebView.new_with_protocol(window, @event_loop.create_proxy, "si\0de", [])
    end

    assert_equal "label contains null byte", error.message
  ensure
    window&.close
  end

  def test_a_label_that_is_not_valid_utf8_is_refused
    assert_raises(EncodingError) { Tokra::Native::Window.new(@event_loop, "\xFF".b.force_encoding(Encoding::UTF_8)) }
  end
end
