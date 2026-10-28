# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# How a real app ends: the loop's LoopDestroyed event reaches plugins as
# RunEvent::Exit, the process takes the status AppHandle#exit was given, and
# Ruby's own exit runs (at_exit, buffered stdout) because the native loop
# ends with SystemExit rather than process::exit (Plan 018, decision 4).
#
# Closing the window by hand is the one path not driven here:
#
#   bundle exec ruby test/integration/fixtures/exit_paths/app.rb --wait
class ExitPathsTest < RealApp::TestCase
  # A status no failure path produces.
  EXIT_CODE = 7

  # Seconds Ctrl-C may take to end the app; the loop exits on its next turn.
  INTERRUPT_GRACE = 15

  # Seconds the waiting app is left idle after its report before SIGTERM.
  SETTLE = 1

  # Seconds SIGTERM may take to end the idle app (Plan 034).
  TERM_GRACE = 2

  # Waits with no exit of its own, and gets SIGTERM once the page has
  # reported and the loop has gone idle.
  def terminated
    self.class.fixture_run(:terminated) do
      RealApp.launch("exit_paths", "--wait", "--run-callback", on_line: lambda { |line, pid|
        next false unless line.start_with?("REPORT ")

        sleep SETTLE
        RealApp.signal(pid, :TERM)
      })
    end
  end

  def exited
    self.class.fixture_run(:exited) do
      RealApp.launch("exit_paths", "--exit-code=#{EXIT_CODE}", "--raise-on-page-load")
    end
  end

  # Waits with no exit of its own, and gets Ctrl-C once the page reports.
  def interrupted
    self.class.fixture_run(:interrupted) do
      RealApp.launch("exit_paths", "--wait", on_line: lambda { |line, pid|
        line.start_with?("REPORT ") && RealApp.signal(pid, :INT)
      })
    end
  end

  def test_the_process_takes_the_status_app_handle_exit_was_given
    run = exited
    assert_finished run
    assert_equal EXIT_CODE, run.status, run.describe
  end

  # AppHandle#exit asks first: plugins hear ExitRequested with the code,
  # then Exit (Plan 038).
  def test_plugins_hear_ready_then_the_exit_request_then_exit_and_ruby_runs_its_own_exit
    run = exited
    assert_finished run
    assert_equal ["EVENT ready", "REPORT", "EVENT exit-requested #{EXIT_CODE}", "EVENT exit", "AT_EXIT"], run.kinds,
      run.describe
  end

  def test_an_exception_in_an_event_handler_is_reported_and_the_loop_survives
    run = exited
    assert_finished run
    assert_includes run.stderr, "exit-paths: deliberate page-load failure (RuntimeError)"
    assert_match(/from .*app\.rb:\d+:in 'Tokra::App#dispatch_page_load'/, run.stderr,
      "the report should be the full message with its backtrace")
    assert_equal "PONG", check_detail(run, "loop answers")["reply"]
  end

  # Ctrl-C is no exit request: nothing can prevent it (Plan 038,
  # decision 7).
  def test_ctrl_c_ends_the_loop_with_status_zero_and_plugins_hear_exit
    run = interrupted
    assert_finished run
    refute_nil run.exit_after_signal, "the page never reported, so Ctrl-C was never sent\n#{run.describe}"
    assert_operator run.exit_after_signal, :<, INTERRUPT_GRACE, "the app outlived Ctrl-C\n#{run.describe}"
    refute_includes run.stderr, "Interrupt", "Ruby's own SIGINT handler ran instead of the loop's"
    assert_equal 0, run.status, run.describe
    assert_equal ["EVENT ready", "REPORT", "EVENT exit", "AT_EXIT"], run.kinds, run.describe
  end

  # Ruby's SIGTERM unwinds the loop, so plugins and the run callback hear
  # RunEvent::Exit, the way ensure code runs, where Tauri's process would
  # simply end (Plan 034, decision 1); the process still ends by the signal.
  # It asks no one first: no ExitRequested (Plan 038, decision 7).
  def test_sigterm_on_an_idle_app_emits_exit_and_ends_by_the_signal
    run = terminated
    assert_finished run
    refute_nil run.exit_after_signal, "the page never reported, so SIGTERM was never sent\n#{run.describe}"
    assert_operator run.exit_after_signal, :<, TERM_GRACE, "the app outlived SIGTERM\n#{run.describe}"
    assert_equal Signal.list.fetch("TERM"), run.termsig, run.describe
    assert_equal ["EVENT ready", "REPORT", "EVENT exit", "RUN exit", "AT_EXIT"], run.kinds, run.describe
  end
end
