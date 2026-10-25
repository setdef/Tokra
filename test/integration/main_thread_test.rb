# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Window and webview calls from background Ruby threads, in a real window.
#
# Tauri never touches a window or webview off the main thread: its runtime
# runs a call at once on the main thread and otherwise posts it through the
# event loop proxy (tauri-runtime-wry send_user_message), and a getter waits
# on a channel the main thread answers (getter!). Tokra's native layer
# refuses another thread outright, so each check here fails with a
# ThreadError, or hangs, if the call skips the dispatch (Plan 020).
class MainThreadTest < RealApp::TestCase
  # A status no failure path produces.
  EXIT_CODE = 9

  def exited
    self.class.fixture_run(:exited) do
      RealApp.launch("main_thread", "--exit-code=#{EXIT_CODE}")
    end
  end

  def test_a_background_thread_runs_while_the_loop_waits
    assert_equal "woke", check_detail(exited, "a background thread runs while the loop waits")["reply"]
  end

  def test_a_background_thread_evaluates_script_through_the_main_thread
    detail = check_detail(exited, "a background thread evaluates script")
    assert_equal "evaluated", detail["evaluated"]
  end

  def test_a_background_thread_reads_the_title_through_the_main_thread
    detail = check_detail(exited, "a background thread reads and sets the title")
    assert_equal "Tokra integration: main thread", detail["before"]
  end

  def test_run_on_main_thread_runs_the_block_on_the_main_thread
    assert check_detail(exited, "run_on_main_thread runs on the main thread")["onMain"]
  end

  # The handler reads the title on the main thread, so it runs at once
  # instead of waiting on a loop it is blocking. The title it reads is the
  # one the background thread set, so the set reached the window too.
  def test_a_main_thread_handler_that_reads_the_title_does_not_wait_on_itself
    detail = check_detail(exited, "a main-thread handler reads the title without waiting on itself")
    assert_equal "set from a thread", detail["title"]
  end

  # Ruby raises a thread's SystemExit in the main thread, where the loop
  # ends with its code; the thread runs at all only because the loop hands
  # it the GVL.
  def test_exit_from_a_background_thread_ends_the_app_with_its_code
    run = exited
    assert_finished run
    assert_equal EXIT_CODE, run.status, run.describe
    assert_equal ["EVENT ready", "REPORT", "EVENT exit"], run.kinds.first(3), run.describe
  end

  def test_a_thread_waiting_as_the_loop_ends_gets_failed_to_receive_message
    run = exited
    assert_finished run
    assert_includes run.lines, "WAITER runtime error: failed to receive message from webview", run.describe
  end

  def test_a_call_from_another_thread_after_the_loop_ends_gets_failed_to_send_message
    run = exited
    assert_finished run
    assert_includes run.lines, "LATE runtime error: failed to send message to the webview", run.describe
    assert_equal "AT_EXIT", run.lines.last, run.describe
  end
end
