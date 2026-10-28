# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "timeout"
require_relative "../support/stub_native"

# A real App, AppHandle, Window, and Webview dispatching native calls to the
# main thread, as Tauri's runtime does (tauri-runtime-wry send_user_message).
# StubNative's loop delivers the injected Native::TaskEvent the way the real
# loop delivers one per queued task.
class TestMainThreadDispatch < Minitest::Test
  def setup
    StubNative.clear_event
  end

  def teardown
    StubNative.clear_event
  end

  def native_window
    StubNative.windows.last
  end

  def native_webview
    StubNative::WebView.instances.last
  end

  # Runs the app, calling +on_ready+ with the handle once it is ready, and
  # delivering +tasks+ TaskEvents after it.
  def run_app(tasks: 1, &on_ready)
    StubNative.inject_event(Array.new(tasks) { Tokra::Native::TaskEvent.new })
    Tokra::Builder.default.run(native: StubNative) do |handle, event|
      on_ready&.call(handle) if event.is_a?(Tokra::RunEvent::Ready)
    end
  end

  def test_set_title_from_another_thread_waits_for_the_main_thread
    title_before_task = nil
    run_app do |handle|
      Thread.new { handle.get_window("main").set_title("from a thread") }.join
      title_before_task = native_window.title
    end

    assert_equal "Tokra", title_before_task, "the native window changed off the main thread"
    assert_equal "from a thread", native_window.title
  end

  def test_set_size_from_another_thread_waits_for_the_main_thread
    run_app do |handle|
      size = Tokra::LogicalSize.new(width: 320, height: 240)
      Thread.new { handle.get_window("main").set_size(size) }.join
      assert_nil native_window.requests[:set_inner_size]
    end

    assert_equal [[false, 320.0, 240.0]], native_window.requests[:set_inner_size]
  end

  def test_eval_from_another_thread_waits_for_the_main_thread
    evals_before_task = nil
    run_app do |handle|
      Thread.new { handle.get_webview("main").eval("1 + 1") }.join
      evals_before_task = native_webview.evals.dup
    end

    assert_empty evals_before_task
    assert_equal ["1 + 1"], native_webview.evals
  end

  def test_emit_from_another_thread_evaluates_on_the_main_thread
    run_app do |handle|
      Thread.new { handle.emit("ready", { "n" => 1 }) }.join
      assert_empty native_webview.evals
    end

    assert_equal 1, native_webview.evals.size
    assert_includes native_webview.evals.first, "ready"
  end

  def test_title_from_another_thread_returns_the_main_threads_answer
    reader = nil
    run_app do |handle|
      reader = Thread.new { handle.get_window("main").title }
      Thread.pass until reader.status == "sleep" || !reader.alive?
    end

    assert_equal "Tokra", reader.value
  end

  def test_title_on_the_main_thread_answers_at_once
    title = nil
    run_app(tasks: 0) { |handle| title = Timeout.timeout(5) { handle.get_window("main").title } }

    assert_equal "Tokra", title
  end

  def test_a_failed_evaluation_is_logged_not_raised
    assert_output(nil, /evaluation failed/) do
      run_app(tasks: 0) { |handle| handle.get_webview("main").eval(StubNative::WebView::FAILING_SCRIPT) }
    end
  end

  def test_run_on_main_thread_from_each_handle_runs_on_the_main_thread
    ran_on = []
    main = Thread.current
    run_app(tasks: 4) do |handle|
      app_handle = handle
      window = handle.get_window("main")
      webview = handle.get_webview("main")
      Thread.new do
        [app_handle, window, webview, webview.window].each do |target|
          target.run_on_main_thread { ran_on << Thread.current }
        end
      end.join
      assert_empty ran_on
    end

    assert_equal [main] * 4, ran_on
  end

  def test_app_run_on_main_thread_runs_at_once_on_the_main_thread
    ran_on = nil
    app = Tokra::Builder.default.build(native: StubNative)
    app.run_on_main_thread { ran_on = Thread.current }

    assert_same Thread.current, ran_on
  end

  def test_after_the_loop_ends_a_call_from_another_thread_fails_with_failed_to_send_message
    handle = nil
    run_app(tasks: 0) { |h| handle = h }

    error = Thread.new do
      handle.get_window("main").set_title("too late")
    rescue Tokra::Error::Runtime => e
      e
    end.value
    assert_instance_of Tokra::Error::Runtime, error
    assert_equal "runtime error: failed to send message to the webview", error.message
  end

  def test_a_getter_waiting_when_the_loop_ends_fails_with_failed_to_receive_message
    reader = nil
    run_app(tasks: 0) do |handle|
      reader = Thread.new do
        handle.get_window("main").title
      rescue Tokra::Error::Runtime => e
        e
      end
      Thread.pass until reader.status == "sleep" || !reader.alive?
    end

    error = reader.join(5)&.value
    refute_nil error, "the getter still waits after the loop ended"
    assert_equal "runtime error: failed to receive message from webview", error.message
  end
end
