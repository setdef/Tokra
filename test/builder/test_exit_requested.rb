# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# How an app asks to close a window and to exit, and how a handler keeps
# either from happening (Plan 038).
#
# Mirrors tauri-runtime-wry's handle_event_loop (lib.rs:4168-4232) and
# on_close_requested (lib.rs:4262-4290): a close request runs the
# listeners and the run callback, then drops the window unless prevented;
# the window's Destroyed event removes it, and with no window left the loop
# emits RunEvent::ExitRequested(code: nil) and exits unless prevented.
# AppHandle#exit sends RequestExit through the loop, which emits
# ExitRequested with its code.
class TestBuilderExitRequested < Minitest::Test
  # Plugin recording the run events it hears, and running +reaction+ on
  # each.
  class RecordingPlugin < Tokra::Plugin
    attr_reader :events
    attr_accessor :reaction

    def initialize(app = nil, config = {})
      super
      @events = []
      @reaction = nil
    end

    def name = "recording"

    def on_event(app, event)
      @events << event
      @reaction&.call(app, event)
    end
  end

  def setup
    StubNative.clear_event
    @plugin = RecordingPlugin.new
  end

  def teardown
    StubNative.clear_event
  end

  def test_closing_the_last_window_asks_to_exit_and_the_loop_ends_with_zero
    app = build
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    app.run

    assert_equal [
      Tokra::RunEvent::Ready,
      [Tokra::RunEvent::WindowEvent, Tokra::WindowEvent::CloseRequested],
      [Tokra::RunEvent::WindowEvent, Tokra::WindowEvent::Destroyed],
      Tokra::RunEvent::ExitRequested,
      Tokra::RunEvent::Exit,
    ], kinds, "close request, destroyed, exit request, then exit"
    assert_nil exit_requests.first.code, "the last window closing asks with no code"
    assert_equal 0, StubNative.exit_code
  end

  def test_an_unprevented_close_closes_the_native_window_and_its_webview
    app = build
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    app.run

    assert_predicate StubNative.windows.first, :closed?
    assert_predicate StubNative::WebView.instances.first, :closed?
    assert_empty app.handle.windows, "on_window_close removes the window"
    assert_empty app.handle.webviews, "and its webviews"
  end

  def test_prevent_close_keeps_the_window_open_and_the_loop_running
    app = build
    @plugin.reaction = lambda { |_app, event|
      event.event.api.prevent_close if close_requested?(event)
    }
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    app.run

    refute_predicate StubNative.windows.first, :closed?
    refute_nil app.handle.get_window("main")
    assert_equal [
      Tokra::RunEvent::Ready,
      [Tokra::RunEvent::WindowEvent, Tokra::WindowEvent::CloseRequested],
      Tokra::RunEvent::Exit,
], kinds
    assert_nil StubNative.exit_code, "only the loop running out of events ended it"
  end

  def test_prevent_exit_keeps_the_loop_running_with_no_window
    app = build
    @plugin.reaction = -> (_app, event) { event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested) }
    StubNative.inject_event([Tokra::Native::WindowCloseEvent.new, Tokra::Native::TaskEvent.new])

    app.run

    assert_predicate StubNative.windows.first, :closed?
    assert_nil StubNative.exit_code, "the prevented request must not end the loop"
    assert_empty app.handle.windows
  end

  def test_app_handle_exit_asks_with_its_code_and_the_loop_ends_with_it
    app = build
    returned = :unset
    app.run { |handle, event| returned = handle.exit(7) if event.is_a?(Tokra::RunEvent::Ready) }

    assert_nil returned, "exit returns, as Tauri's request does"
    assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit], kinds
    assert_equal 7, exit_requests.first.code
    assert_equal 7, StubNative.exit_code
  end

  def test_a_prevented_exit_request_keeps_running_until_one_is_not
    app = build
    app.run do |handle, event|
      handle.exit(3) if event.is_a?(Tokra::RunEvent::Ready)
      if event.is_a?(Tokra::RunEvent::ExitRequested) && event.code == 3
        event.api.prevent_exit
        handle.exit(4)
      end
    end

    assert_equal [3, 4], exit_requests.map(&:code)
    assert_equal 4, StubNative.exit_code
  end

  def test_prevent_exit_is_ignored_for_the_restart_code
    app = build
    app.run do |handle, event|
      handle.exit(Tokra::RESTART_EXIT_CODE) if event.is_a?(Tokra::RunEvent::Ready)
      event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested)
    end

    assert_equal Tokra::RESTART_EXIT_CODE, StubNative.exit_code
  end

  def test_plugins_hear_the_exit_request_before_the_run_callback
    order = []
    app = build
    @plugin.reaction = -> (_app, event) { order << :plugin if event.is_a?(Tokra::RunEvent::ExitRequested) }
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    app.run { |_handle, event| order << :callback if event.is_a?(Tokra::RunEvent::ExitRequested) }

    assert_equal [:plugin, :callback], order
  end

  def test_a_raising_exit_handler_is_reported_and_the_exit_still_happens
    app = build
    @plugin.reaction = lambda { |_app, event|
      raise "deliberate exit-request failure" if event.is_a?(Tokra::RunEvent::ExitRequested)
    }
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    _, stderr = capture_io { app.run }

    assert_includes stderr, "deliberate exit-request failure (RuntimeError)"
    assert_equal 0, StubNative.exit_code
  end

  def test_a_raising_close_handler_is_reported_and_the_window_still_closes
    app = build
    @plugin.reaction = lambda { |_app, event|
      raise "deliberate close failure" if close_requested?(event)
    }
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    _, stderr = capture_io { app.run }

    assert_includes stderr, "deliberate close failure (RuntimeError)"
    assert_predicate StubNative.windows.first, :closed?
  end

  def test_the_window_is_gone_from_the_manager_before_handlers_hear_destroyed
    seen = []
    app = Tokra::Builder.default
      .on_window_event(&Ractor.shareable_proc { |_window, event|
        Thread.current[:exit_requested_order] << :listener if event.is_a?(Tokra::WindowEvent::Destroyed)
      })
      .build(native: StubNative)
    Thread.current[:exit_requested_order] = seen
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    app.run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::WindowEvent) && event.event.is_a?(Tokra::WindowEvent::Destroyed)

      seen << [:callback, handle.get_window("main")]
    end

    assert_equal [[:callback, nil], :listener], seen,
      "the run callback hears Destroyed after on_window_close, then the listeners (lib.rs:4134-4150)"
  ensure
    Thread.current[:exit_requested_order] = nil
  end

  def test_exit_from_another_thread_reaches_the_loop
    app = build
    app.run { |handle, event| Thread.new { handle.exit(5) }.join if event.is_a?(Tokra::RunEvent::Ready) }

    assert_equal 5, StubNative.exit_code
  end

  def test_exit_before_run_waits_for_the_loop
    app = build
    app.handle.exit(6)

    app.run

    assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit], kinds
    assert_equal 6, StubNative.exit_code
  end

  def test_exit_after_the_loop_has_ended_exits_the_process_with_its_code
    app = build
    app.run

    error = assert_raises(SystemExit) { app.handle.exit(9) }
    assert_equal 9, error.status
  end

  def test_window_close_asks_on_a_later_turn_not_inside_the_caller
    app = build
    during_ready = nil
    app.run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      handle.get_window("main").close
      during_ready = kinds
    end

    assert_equal [Tokra::RunEvent::Ready], during_ready, "close must not run handlers inside its caller"
    assert_includes kinds, [Tokra::RunEvent::WindowEvent, Tokra::WindowEvent::CloseRequested]
    assert_equal 0, StubNative.exit_code
  end

  # A close request for a window the store no longer holds is dropped
  # (on_close_requested, lib.rs:4267-4268). Until its Destroyed event
  # arrives, the store still holds a closed window, as Tauri's does, so the
  # close here is asked for once the window is gone.
  def test_closing_a_window_already_gone_asks_no_one
    app = build
    window = nil
    app.run do |handle, event|
      case event
      when Tokra::RunEvent::Ready
        window = handle.get_window("main")
        window.destroy
      when Tokra::RunEvent::ExitRequested
        event.api.prevent_exit
        window.close
      end
    end

    refute_includes kinds, [Tokra::RunEvent::WindowEvent, Tokra::WindowEvent::CloseRequested]
  end

  # The runtime acts on Destroyed only for a window it still held
  # (lib.rs:4172-4173).
  def test_a_second_destroyed_event_emits_nothing
    app = build
    @plugin.reaction = -> (_app, event) { event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested) }
    StubNative.inject_event([Tokra::Native::WindowCloseEvent.new, Tokra::Native::WindowDestroyedEvent.new])

    app.run

    assert_equal 1, kinds.count([Tokra::RunEvent::WindowEvent, Tokra::WindowEvent::Destroyed])
    assert_equal 1, exit_requests.size
  end

  def test_window_destroy_skips_the_close_request
    app = build
    app.run { |handle, event| handle.get_window("main").destroy if event.is_a?(Tokra::RunEvent::Ready) }

    assert_equal [
      Tokra::RunEvent::Ready,
      [Tokra::RunEvent::WindowEvent, Tokra::WindowEvent::Destroyed],
      Tokra::RunEvent::ExitRequested,
      Tokra::RunEvent::Exit,
    ], kinds
  end

  def test_a_closed_window_title_fails_to_receive_the_answer
    app = build
    window = nil
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)
    app.run { |handle, event| window = handle.get_window("main") if event.is_a?(Tokra::RunEvent::Ready) }

    error = assert_raises(Tokra::Error::Runtime) { window.title }
    assert_equal "runtime error: failed to receive message from webview", error.message
  end

  private def build
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(@plugin)
    app
  end

  # The events the plugin heard, as classes, with a window event's inner
  # class beside it.
  private def kinds
    @plugin.events.map do |event|
      event.is_a?(Tokra::RunEvent::WindowEvent) ? [event.class, event.event.class] : event.class
    end
  end

  private def exit_requests
    @plugin.events.grep(Tokra::RunEvent::ExitRequested)
  end

  private def close_requested?(event)
    event.is_a?(Tokra::RunEvent::WindowEvent) && event.event.is_a?(Tokra::WindowEvent::CloseRequested)
  end
end
