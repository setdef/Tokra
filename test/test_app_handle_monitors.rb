# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "timeout"
require_relative "support/stub_native"

# AppHandle's monitors and cursor (plan 041, decision 1): Tauri reads them
# from the event loop's window target (tauri-runtime-wry
# lib.rs:2662-2695), which Tokra's native loop lends to the main thread.
class TestAppHandleMonitors < Minitest::Test
  def setup
    StubNative.clear_event
  end

  def app
    @app ||= Tokra::Builder.default.build(native: StubNative)
  end

  def handle
    app.handle
  end

  def event_loop
    @event_loop ||= StubNative::EventLoop.new.tap { |target| handle.runtime_context.window_target = target }
  end

  def test_the_monitors_are_the_window_targets
    event_loop
    main = Tokra::Monitor.from_native(StubNative::Window::MONITOR)
    side = Tokra::Monitor.from_native(StubNative::Window::SIDE_MONITOR)

    assert_equal main, handle.primary_monitor
    assert_equal [main, side], handle.available_monitors
    assert_equal side, handle.monitor_from_point(3100, 10)
    assert_nil handle.monitor_from_point(-5, -5)
  end

  def test_the_cursor_is_a_physical_position
    event_loop

    assert_equal Tokra::PhysicalPosition.new(x: 812.0, y: 455.5), handle.cursor_position
  end

  # tao's error becomes FailedToGetCursorPosition (lib.rs:2690-2695).
  def test_a_cursor_the_platform_cannot_read_raises_failed_to_get_cursor_position
    event_loop.cursor = [nil]

    error = assert_raises(Tokra::Error::Runtime) { handle.cursor_position }
    assert_equal "runtime error: failed to get cursor position", error.message
  end

  def test_app_answers_as_its_handle_does
    event_loop

    assert_equal handle.primary_monitor, app.primary_monitor
    assert_equal handle.available_monitors, app.available_monitors
    assert_equal handle.monitor_from_point(1, 1), app.monitor_from_point(1, 1)
    assert_equal handle.cursor_position, app.cursor_position
  end

  # Before App#run builds the loop there is no window target to ask.
  def test_before_the_loop_exists_each_getter_fails_to_receive
    %i[primary_monitor available_monitors cursor_position].each do |getter|
      error = assert_raises(Tokra::Error::Runtime) { handle.public_send(getter) }
      assert_equal "runtime error: failed to receive message from webview", error.message, getter
    end
  end

  # Tauri's runtime exists before the setup hook runs, so the hook can ask.
  def test_the_setup_hook_and_the_run_callback_can_ask
    setup = Ractor.shareable_proc { |built| Thread.current[:setup_monitor] = built.primary_monitor }
    app = Tokra::Builder.default.setup(&setup).build(native: StubNative)
    ready = nil
    begin
      app.run do |handle, event|
        ready = handle.cursor_position if event.is_a?(Tokra::RunEvent::Ready)
      end
    rescue SystemExit
      nil
    end

    assert_equal Tokra::Monitor.from_native(StubNative::Window::MONITOR), Thread.current[:setup_monitor]
    assert_equal Tokra::PhysicalPosition.new(x: 812.0, y: 455.5), ready
  ensure
    Thread.current[:setup_monitor] = nil
  end

  def test_from_another_thread_the_main_thread_answers
    event_loop
    answer = Thread.new { handle.primary_monitor }
    Timeout.timeout(5) do
      Thread.pass until answer.status == "sleep" || !answer.alive?
      handle.runtime_context.handle_task
    end

    assert_equal Tokra::Monitor.from_native(StubNative::Window::MONITOR), answer.value
  end
end
