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

  # Plan 040's getters answer nil for a closed window, and its setters
  # do nothing, so Tokra::Window raises or ignores as plan 038 decided.
  def test_a_closed_window_answers_nil_to_every_getter_and_ignores_every_setter
    @window.close

    GETTERS.each { |getter, args| assert_nil @window.public_send(getter, *args), getter }
    SETTERS.each { |setter, args| assert_nil @window.public_send(setter, *args), setter }
  end

  # An open window answers each getter in the shape Tokra::Window reads.
  def test_an_open_window_answers_each_getter_in_its_shape
    assert_kind_of Float, @window.scale_factor
    assert_includes [true, false], @window.is_visible
    assert_includes %w[Light Dark], @window.theme
    width, height = @window.outer_size
    assert_kind_of Integer, width
    assert_kind_of Integer, height
    assert_equal 1, @window.outer_position.size
    monitors = @window.available_monitors
    refute_empty monitors
    name, position, size, work_area, scale_factor = monitors.first
    assert(name.nil? || name.is_a?(String))
    assert_equal 2, position.size
    assert_equal 2, size.size
    assert_equal 2, work_area.size
    assert_kind_of Float, scale_factor
  end

  def test_a_name_the_ruby_enum_lacks_raises_argument_error
    assert_raises(ArgumentError) { @window.drag_resize_window("Up") }
    assert_raises(ArgumentError) { @window.request_user_attention("Urgent") }
    assert_raises(ArgumentError) { @window.set_theme("Sepia") }
  end

  def test_getters_and_setters_off_the_windows_thread_raise_thread_error
    %i[scale_factor is_visible theme available_monitors].each do |getter|
      error = assert_raises(ThreadError) { quietly { @window.public_send(getter) } }
      assert_equal "Tokra::Native::Window can only be used on the thread that created it", error.message, getter
    end
    assert_raises(ThreadError) { quietly { @window.set_resizable(false) } }
  end

  # Each getter Native::Window gained in plan 040, with its arguments.
  GETTERS = {
    scale_factor: [],
    inner_position: [],
    outer_position: [],
    inner_size: [nil],
    outer_size: [],
    is_fullscreen: [],
    is_minimized: [],
    is_maximized: [],
    is_focused: [],
    is_decorated: [],
    is_resizable: [],
    is_maximizable: [],
    is_minimizable: [],
    is_closable: [],
    is_visible: [],
    is_always_on_top: [],
    theme: [],
    current_monitor: [],
    primary_monitor: [],
    monitor_from_point: [0.0, 0.0],
    available_monitors: [],
  }.freeze

  # Each setter Native::Window gained in plan 040, with its arguments.
  SETTERS = {
    center: [],
    request_user_attention: ["Informational"],
    set_resizable: [false],
    set_maximizable: [false],
    set_minimizable: [false],
    set_closable: [false],
    set_maximized: [true],
    set_minimized: [true],
    set_visible: [false],
    set_decorations: [false],
    set_always_on_bottom: [true],
    set_visible_on_all_workspaces: [true],
    set_content_protection: [true],
    set_focusable: [false],
    set_cursor_visible: [false],
    set_inner_size: [[false, 10.0, 10.0]],
    set_min_inner_size: [nil],
    set_max_inner_size: [[true, 10.0, 10.0]],
    set_outer_position: [[false, 1.0, 1.0]],
    set_fullscreen: [true],
    set_simple_fullscreen: [true],
    set_focus: [],
    set_skip_taskbar: [true],
    set_cursor_grab: [true],
    set_cursor_icon: ["Wait"],
    set_cursor_position: [[true, 1.0, 1.0]],
    drag_window: [],
    drag_resize_window: ["East"],
    set_theme: ["Dark"],
  }.freeze

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
