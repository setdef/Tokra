# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# A closed Native::Window and Native::WebView, against the real extension
# (Plan 038, decision 3). Tauri's runtime ignores a message for a window
# or webview it no longer holds and leaves a getter's channel unanswered
# (tauri-runtime-wry lib.rs:3244-3250); Tokra's closed objects ignore
# setters and scripts and answer nil or Unavailable.
class TestNativeClosedWindow < Minitest::Test
  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
    @proxy = @event_loop.create_proxy
    @window = Tokra::Native::Window.new(@event_loop)
  end

  def test_a_closed_window_ignores_setters_and_answers_nil_and_unavailable
    refute_nil @window.title
    refute_nil @window.id

    assert_nil @window.close

    assert_nil @window.set_title("ignored")
    assert_nil @window.set_size(100.0, 100.0)
    assert_nil @window.set_always_on_top(true)
    assert_nil @window.set_ignore_cursor_events(true)
    assert_nil @window.title
    assert_nil @window.id
    assert_equal [:Unavailable], @window.raw_window_handle
    assert_equal [:Unavailable], @window.raw_display_handle
  end

  def test_closing_a_window_twice_does_nothing
    @window.close
    assert_nil @window.close
  end

  def test_closing_a_window_off_its_thread_raises_thread_error
    error = assert_raises(ThreadError) { quietly { @window.close } }
    assert_equal "Tokra::Native::Window can only be used on the thread that created it", error.message
    refute_nil @window.title, "the window stays open"
  end

  def test_a_closed_webview_ignores_scripts_and_closes_once
    webview = Tokra::Native::WebView.new_with_protocol(@window, @proxy, [])

    assert_nil webview.close
    assert_nil webview.eval("throw new Error('never evaluated')")
    assert_nil webview.close
  end

  def test_closing_a_webview_off_its_thread_raises_thread_error
    webview = Tokra::Native::WebView.new_with_protocol(@window, @proxy, [])

    error = assert_raises(ThreadError) { quietly { webview.close } }
    assert_equal "Tokra::Native::WebView can only be used on the thread that created it", error.message
  end

  # Runs the block on another thread and returns its value, raising what it
  # raised without Ruby's report of the thread's death.
  private def quietly(&block)
    Thread.new do
      Thread.current.report_on_exception = false
      block.call
    end.value
  end

  def teardown
    @window&.close
  end
end
