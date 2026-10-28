# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "timeout"
require_relative "support/stub_native"

# Tokra::Window's getters and setters (plan 040) through a real AppHandle
# and the stub native window, which answers in Native::Window's shapes.
# The tests run on the thread that built the handle, the main thread, where
# a setter runs at once.
class TestWindowState < Minitest::Test
  def app_handle
    @app_handle ||= Tokra::Builder.default.build(native: StubNative).handle
  end

  def native
    @native ||= StubNative::Window.new(nil)
  end

  def window
    @window ||= Tokra::Window.new(label: "win", native:, app_handle:)
  end

  def test_scale_factor_is_the_native_answer
    native.state[:scale_factor] = 1.5

    assert_in_delta 1.5, window.scale_factor
  end

  def test_positions_are_physical_positions
    assert_equal Tokra::PhysicalPosition.new(x: 20, y: 84), window.inner_position
    assert_equal Tokra::PhysicalPosition.new(x: 20, y: 28), window.outer_position
  end

  # tao's NotSupportedError reaches Tauri's caller as FailedToSendMessage
  # (tauri-runtime-wry lib.rs:3261-3276).
  def test_an_unsupported_position_raises_failed_to_send_message
    native.state[:inner_position] = [nil]
    native.state[:outer_position] = [nil]

    %i[inner_position outer_position].each do |getter|
      error = assert_raises(Tokra::Error::Runtime) { window.public_send(getter) }
      assert_equal "runtime error: failed to send message to the webview", error.message
    end
  end

  def test_sizes_are_physical_sizes
    assert_equal Tokra::PhysicalSize.new(width: 1600, height: 1200), window.inner_size
    assert_equal Tokra::PhysicalSize.new(width: 1600, height: 1256), window.outer_size
  end

  def test_flags_are_the_native_answers
    flags = %i[
      is_fullscreen
      is_minimized
      is_maximized
      is_focused
      is_decorated
      is_resizable
      is_maximizable
      is_minimizable
      is_closable
      is_visible
      is_always_on_top
    ]
    flags.each { |flag| native.state[flag] = true }
    flags.each { |flag| assert_same true, window.public_send(flag), flag }
    flags.each { |flag| native.state[flag] = false }
    flags.each { |flag| assert_same false, window.public_send(flag), flag }
  end

  def test_theme_is_a_theme
    assert_same Tokra::Theme::Light, window.theme
    native.state[:theme] = "Dark"

    assert_same Tokra::Theme::Dark, window.theme
  end

  def test_monitors_are_monitors
    monitor = window.current_monitor

    assert_equal "Stub Display", monitor.name
    assert_equal Tokra::PhysicalSize.new(width: 3024, height: 1964), monitor.size
    assert_equal Tokra::PhysicalPosition.new(x: 0, y: 0), monitor.position
    assert_equal Tokra::PhysicalRect.new(
      position: Tokra::PhysicalPosition.new(x: 0, y: 74),
      size: Tokra::PhysicalSize.new(width: 3024, height: 1890)
    ), monitor.work_area
    assert_in_delta 2.0, monitor.scale_factor
    assert_equal monitor, window.primary_monitor
    assert_equal [monitor.name, nil], window.available_monitors.map(&:name)
  end

  def test_monitor_from_point_finds_the_monitor_holding_it_or_none
    assert_equal "Stub Display", window.monitor_from_point(10, 10).name
    assert_equal Tokra::PhysicalPosition.new(x: 3024, y: 0), window.monitor_from_point(3100.0, 10.0).position
    assert_nil window.monitor_from_point(-10, -10)
  end

  def test_no_current_monitor_is_nil
    native.state[:current_monitor] = [nil]
    native.state[:primary_monitor] = [nil]

    assert_nil window.current_monitor
    assert_nil window.primary_monitor
  end

  # Tauri's runtime leaves a closed window's getter unanswered
  # (lib.rs:3244-3250), and its caller fails to receive.
  def test_every_getter_on_a_closed_window_raises_failed_to_receive_message
    native.close
    getters = %i[
      scale_factor
      inner_position
      outer_position
      inner_size
      outer_size
      is_fullscreen
      is_minimized
      is_maximized
      is_focused
      is_decorated
      is_resizable
      is_maximizable
      is_minimizable
      is_closable
      is_visible
      is_always_on_top
      theme
      current_monitor
      primary_monitor
      available_monitors
      title
    ]

    getters.each do |getter|
      error = assert_raises(Tokra::Error::Runtime, getter.to_s) { window.public_send(getter) }
      assert_equal "runtime error: failed to receive message from webview", error.message
    end
    assert_raises(Tokra::Error::Runtime) { window.monitor_from_point(0, 0) }
  end

  def test_flag_setters_change_what_the_getters_read
    {
      set_resizable: :is_resizable,
      set_maximizable: :is_maximizable,
      set_minimizable: :is_minimizable,
      set_closable: :is_closable,
      set_decorations: :is_decorated,
      set_fullscreen: :is_fullscreen,
    }.each do |setter, getter|
      assert_nil window.public_send(setter, false)
      assert_same false, window.public_send(getter), getter
      window.public_send(setter, true)
      assert_same true, window.public_send(getter), getter
    end
  end

  def test_actions_ask_tao_for_the_state_tauri_names
    window.maximize
    assert_same true, window.is_maximized
    window.unmaximize
    assert_same false, window.is_maximized
    window.minimize
    assert_same true, window.is_minimized
    window.unminimize
    assert_same false, window.is_minimized
    window.hide
    assert_same false, window.is_visible
    window.show
    assert_same true, window.is_visible
  end

  def test_set_simple_fullscreen_asks_for_simple_fullscreen
    window.set_simple_fullscreen(true)

    assert_equal [true], native.requests[:set_simple_fullscreen]
  end

  def test_setters_pass_their_values_to_tao
    window.set_always_on_bottom(true)
    window.set_visible_on_all_workspaces(true)
    window.set_content_protected(true)
    window.set_focusable(false)
    window.set_skip_taskbar(true)
    window.set_cursor_grab(true)
    window.set_cursor_visible(false)
    window.center
    window.set_focus
    window.start_dragging

    expected = {
      set_always_on_bottom: [true],
      set_visible_on_all_workspaces: [true],
      set_content_protection: [true],
      set_focusable: [false],
      set_skip_taskbar: [true],
      set_cursor_grab: [true],
      set_cursor_visible: [false],
      center: [],
      set_focus: [],
      drag_window: [],
    }
    assert_equal expected, native.requests
  end

  def test_enum_setters_pass_the_names_tao_maps
    window.set_cursor_icon(Tokra::CursorIcon::NeswResize)
    window.start_resize_dragging(Tokra::ResizeDirection::SouthWest)
    window.request_user_attention(Tokra::UserAttentionType::Critical)
    window.set_theme(Tokra::Theme::Dark)

    assert_equal ["NeswResize"], native.requests[:set_cursor_icon]
    assert_equal ["SouthWest"], native.requests[:drag_resize_window]
    assert_equal ["Critical"], native.requests[:request_user_attention]
    assert_equal ["Dark"], native.requests[:set_theme]
  end

  # Tauri's None: cancel the request, follow the system's theme.
  def test_nil_cancels_attention_and_follows_the_system_theme
    window.request_user_attention(nil)
    window.set_theme(nil)

    assert_equal [nil], native.requests[:request_user_attention]
    assert_equal [nil], native.requests[:set_theme]
  end

  def test_sizes_and_positions_reach_tao_as_their_kind
    window.set_size(Tokra::PhysicalSize.new(width: 640, height: 480))
    window.set_min_size(Tokra::LogicalSize.new(width: 200, height: 100.5))
    window.set_max_size(nil)
    window.set_position(Tokra::LogicalPosition.new(x: -10, y: 20))
    window.set_cursor_position(Tokra::PhysicalPosition.new(x: 5, y: 6))

    assert_equal [[true, 640.0, 480.0]], native.requests[:set_inner_size]
    assert_equal [[false, 200.0, 100.5]], native.requests[:set_min_inner_size]
    assert_equal [nil], native.requests[:set_max_inner_size]
    assert_equal [[false, -10.0, 20.0]], native.requests[:set_outer_position]
    assert_equal [[true, 5.0, 6.0]], native.requests[:set_cursor_position]
  end

  # Rust's Into<Size> would not compile; Ruby raises on the caller's
  # thread, before anything reaches the main thread.
  def test_a_wrong_argument_raises_type_error_and_sends_nothing
    {
      set_size: [800, 600],
      set_min_size: Tokra::LogicalPosition.new(x: 1, y: 1),
      set_position: Tokra::LogicalSize.new(width: 1, height: 1),
      set_cursor_position: [1, 1],
      set_cursor_icon: :wait,
      start_resize_dragging: "East",
      request_user_attention: :critical,
      set_theme: "Dark",
    }.each do |setter, argument|
      assert_raises(TypeError, setter.to_s) { window.public_send(setter, argument) }
    end
    error = assert_raises(TypeError) { window.set_size(nil) }
    assert_equal "wrong argument type NilClass (expected Tokra::LogicalSize or Tokra::PhysicalSize)", error.message
    error = assert_raises(TypeError) { window.set_cursor_icon(:wait) }
    assert_equal "wrong argument type Symbol (expected Tokra::CursorIcon)", error.message
    assert_empty native.requests
  end

  def test_a_closed_window_ignores_setters
    native.close

    assert_nil window.set_resizable(false)
    assert_nil window.set_size(Tokra::LogicalSize.new(width: 1, height: 1))
    assert_nil window.center
    assert_empty native.requests
  end

  def test_setters_return_nil
    assert_nil window.maximize
    assert_nil window.set_theme(nil)
    assert_nil window.set_position(Tokra::PhysicalPosition.new(x: 0, y: 0))
  end

  def test_after_the_loop_has_ended_a_getter_from_another_thread_fails_to_send
    app_handle.runtime_context.close

    error = Thread.new do
      window.is_visible
    rescue Tokra::Error::Runtime => e
      e
    end.value

    assert_equal "runtime error: failed to send message to the webview", error.message
  end

  # Tauri's monitor_from_point drops the send's error and fails on the
  # channel (tauri-runtime-wry lib.rs:1954-1967).
  def test_after_the_loop_has_ended_monitor_from_point_fails_to_receive
    app_handle.runtime_context.close

    error = Thread.new do
      window.monitor_from_point(0, 0)
    rescue Tokra::Error::Runtime => e
      e
    end.value

    assert_equal "runtime error: failed to receive message from webview", error.message
  end
end

# The getters and setters inside a running app, from the main thread and
# from another, and inner_size's webview (plan 040, decision 6).
class TestWindowStateInAnApp < Minitest::Test
  def setup
    StubNative.clear_event
  end

  def teardown
    StubNative.clear_event
  end

  def run_app(tasks: 1, &on_ready)
    StubNative.inject_event(Array.new(tasks) { Tokra::Native::TaskEvent.new })
    Tokra::Builder.default.run(native: StubNative) do |handle, event|
      on_ready&.call(handle) if event.is_a?(Tokra::RunEvent::Ready)
    end
  end

  # Tauri's runtime measures the window's webview on macOS
  # (tauri-runtime-wry lib.rs:5195-5212); the native window gets it.
  def test_inner_size_hands_the_native_window_its_webview
    run_app(tasks: 0) { |handle| handle.get_window("main").inner_size }

    assert_same StubNative::WebView.instances.last, StubNative.windows.last.inner_size_webview
  end

  def test_a_getter_from_another_thread_returns_the_main_threads_answer
    reader = nil
    run_app do |handle|
      StubNative.windows.last.state[:is_maximized] = true
      reader = Thread.new { handle.get_window("main").is_maximized }
      Thread.pass until reader.status == "sleep" || !reader.alive?
    end

    assert_same true, reader.value
  end

  def test_a_setter_from_another_thread_waits_for_the_main_thread
    run_app do |handle|
      Thread.new { handle.get_window("main").set_resizable(false) }.join
      assert_same true, StubNative.windows.last.state[:is_resizable]
    end

    assert_same false, StubNative.windows.last.state[:is_resizable]
  end

  def test_a_main_thread_getter_answers_at_once
    visible = nil
    run_app(tasks: 0) { |handle| visible = Timeout.timeout(5) { handle.get_window("main").is_visible } }

    assert_same true, visible
  end
end
