# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The native event loop sharing Ruby's GVL with other threads, in a real
# window (Plan 020, ADR 012). The loop holds the GVL and hands it over once
# per iteration when another thread waits for it; these tests show the
# window keeps turning however busy those threads are, that threads which
# were waiting before the loop started still get their turn, that a signal
# ends the app the way it ends any Ruby program, and that windows,
# webviews, and protocol answers from other threads reach the main thread.
class NativeLoopTest < RealApp::TestCase
  # Ruby's time slice in milliseconds: RUBY_THREAD_TIMESLICE, or 100
  # (Ruby v4.0.1 thread.c:118, 5746-5752). The fixture inherits it.
  TIME_SLICE_MS = Integer(ENV.fetch("RUBY_THREAD_TIMESLICE", "100"))

  # The longest a wake-up should wait: one round of time slices, one for
  # each busy thread, the ticker, and the main thread, since the loop hands
  # the GVL over once per turn; doubled for the timer thread's jitter. How
  # many wake-ups arrive is not bounded: that is how often the ticker itself
  # wins the GVL against the busy threads, which depends on the machine.
  # The failure message reports it; the test does not hold the loop to it,
  # since a loaded machine starves the whole process for longer than that.
  def expected_latency_ms(busy_threads)
    2 * (busy_threads + 2) * TIME_SLICE_MS
  end

  # The longest a wake-up may wait before the test calls the loop frozen.
  # A loop that never hands the GVL over starves the ticker outright, so
  # its wake-ups wait for the whole run or never come; a bound this loose
  # still catches it, and machine load does not reach it.
  FROZEN_MS = 4000

  # Seconds SIGTERM may take to end the app.
  TERM_GRACE = 15

  def cpu_bound(threads, *flags)
    self.class.fixture_run(:"cpu#{threads}#{flags.join}") do
      RealApp.launch("native_loop", "--cpu=#{threads}", *flags)
    end
  end

  def wakeups(run)
    line = run.lines.find { |l| l.start_with?("WAKEUPS ") }
    refute_nil line, "the loop never reported its wake-ups\n#{run.describe}"
    line.split.drop(1).map { |n| Integer(n) }
  end

  # The loop kept turning: it delivered wake-ups, more than one, none of
  # them frozen out, and the exit the last one asked for ended the app.
  def assert_the_window_keeps_turning(run, busy_threads)
    assert_finished run
    assert_equal 0, run.status, run.describe
    count, max = wakeups(run)
    assert_operator count, :>=, 2, "the loop stopped turning\n#{run.describe}"
    assert_operator max, :<, FROZEN_MS,
      "a wake-up waited #{max} ms; one round of time slices is #{expected_latency_ms(busy_threads)} ms\n" \
        "#{run.describe}"
  end

  def test_one_cpu_bound_thread_cannot_freeze_the_window_or_its_exit
    assert_the_window_keeps_turning(cpu_bound(1), 1)
  end

  def test_three_cpu_bound_threads_cannot_freeze_the_window_or_its_exit
    assert_the_window_keeps_turning(cpu_bound(3), 3)
  end

  # The threads, the ticker among them, wait for the GVL before the loop
  # installs its hook, so their READY events have already fired.
  def test_threads_waiting_before_the_loop_starts_still_get_the_gvl
    assert_the_window_keeps_turning(cpu_bound(1, "--before-run"), 1)
  end

  # Ruby's own SIGTERM handler raises SignalException in the main thread;
  # it reaches the loop when the loop hands the GVL to the ticker, ends the
  # loop, and is raised again from EventLoop#run, so Ruby runs at_exit and
  # ends by the signal.
  def test_sigterm_ends_the_app_the_way_it_ends_any_ruby_program
    run = self.class.fixture_run(:term) do
      RealApp.launch("native_loop", "--ticker-wait", on_line: lambda { |line, pid|
        line.start_with?("READY") && RealApp.signal(pid, :TERM)
      })
    end
    assert_finished run
    refute_nil run.exit_after_signal, "the app never said READY\n#{run.describe}"
    assert_operator run.exit_after_signal, :<, TERM_GRACE, "the app outlived SIGTERM\n#{run.describe}"
    assert_equal Signal.list.fetch("TERM"), run.termsig, run.describe
    assert_equal "AT_EXIT", run.lines.last, run.describe
  end

  # Seconds the idle fixture is left alone before each signal, so the
  # window's start-up events are over and only the signal can wake it.
  SETTLE = 1

  # Seconds an idle app may take to act on a signal. The loop looks for
  # one every 100 ms (Plan 034), and a healthy run acts within about that;
  # the margin is for a loaded machine.
  IDLE_GRACE = 2

  # Runs the idle fixture, which has no other thread and gets no event
  # after the one that prints READY (Plan 034). +signals+ maps a line to the
  # signal sent when that line appears, after SETTLE seconds, or to
  # <tt>[signal, seconds]</tt>.
  def idle(key, signals, *flags)
    self.class.fixture_run(key) do
      RealApp.launch("native_loop", "--idle", *flags, on_line: lambda { |line, pid|
        signal, settle = signals[line.chomp]
        next false unless signal

        sleep(settle || SETTLE)
        RealApp.signal(pid, signal)
      })
    end
  end

  # The app ended within IDLE_GRACE of the last signal, having run its
  # ensure clause and at_exit hook.
  def assert_ended_the_ruby_way(run, lines)
    assert_finished run
    refute_nil run.exit_after_signal, "the app was never signalled\n#{run.describe}"
    assert_operator run.exit_after_signal, :<, IDLE_GRACE, "the app outlived the signal\n#{run.describe}"
    assert_equal lines, run.lines, run.describe
  end

  # Nothing but the signal wakes the loop, so the loop must look for Ruby's
  # pending interrupt on its own (Plan 034).
  def test_sigterm_ends_an_idle_app_the_way_it_ends_any_ruby_program
    run = idle(:idle_term, { "READY" => :TERM })
    assert_ended_the_ruby_way run, %w[READY ENSURE AT_EXIT]
    assert_equal Signal.list.fetch("TERM"), run.termsig, run.describe
  end

  # Sent at once, the signal lands while the loop's last turn is fresh.
  def test_sigterm_sent_as_the_loop_starts_ends_the_app
    run = idle(:start_term, { "READY" => [:TERM, 0] })
    assert_ended_the_ruby_way run, %w[READY ENSURE AT_EXIT]
    assert_equal Signal.list.fetch("TERM"), run.termsig, run.describe
  end

  # The USR1 trap gives the loop a turn; SIGTERM follows at once, well
  # within 100 ms of it, so a deadline counted from the loop's last turn
  # has not lapsed, and on Linux tao never wakes for one anyway (Plan 034,
  # decision 2). Only the loop's own once-a-slice wake catches it.
  def test_a_signal_right_after_another_turn_still_ends_the_app
    run = idle(:turn_then_term, { "READY" => :USR1, "TRAPPED USR1" => [:TERM, 0] }, "--trap-usr1")
    assert_ended_the_ruby_way run, ["READY", "TRAPPED USR1", "ENSURE", "AT_EXIT"]
    assert_equal Signal.list.fetch("TERM"), run.termsig, run.describe
  end

  def test_sighup_ends_an_idle_app_the_way_it_ends_any_ruby_program
    run = idle(:idle_hup, { "READY" => :HUP })
    assert_ended_the_ruby_way run, %w[READY ENSURE AT_EXIT]
    assert_equal Signal.list.fetch("HUP"), run.termsig, run.describe
  end

  # The trap runs while the loop idles, and returning from it keeps the app
  # running: only the later SIGTERM ends it.
  def test_an_apps_trap_runs_while_the_loop_is_idle_and_can_keep_it_running
    run = idle(:idle_trap_usr1, { "READY" => :USR1, "TRAPPED USR1" => :TERM }, "--trap-usr1")
    assert_ended_the_ruby_way run, ["READY", "TRAPPED USR1", "ENSURE", "AT_EXIT"]
    assert_equal Signal.list.fetch("TERM"), run.termsig, run.describe
  end

  def test_an_apps_trap_can_end_an_idle_app_with_its_own_status
    run = idle(:idle_trap_term, { "READY" => :TERM }, "--trap-term-exit=3")
    assert_ended_the_ruby_way run, ["READY", "TRAPPED TERM", "ENSURE", "AT_EXIT"]
    assert_equal 3, run.status, run.describe
  end

  # A window freed on another thread would close through tao's synchronous
  # main-thread dispatch while the main thread waits for the GVL; a webview
  # freed there would be destroyed off its thread. Both go home and drop on
  # the main thread, and a released webview stops beating.
  def test_windows_and_webviews_collected_on_another_thread_drop_on_the_main_thread
    run = self.class.fixture_run(:gc_drop) { RealApp.launch("native_loop", "--gc-drop") }
    assert_finished run
    assert_equal 0, run.status, run.describe
    line = run.lines.find { |l| l.start_with?("STILL_BEATING ") }
    refute_nil line, run.describe
    assert_operator Integer(line.split.last), :<, 3, "no collected webview was destroyed\n#{run.describe}"
  end

  def responses
    self.class.fixture_run(:responses) { RealApp.launch("native_loop", "--responses") }
  end

  def test_an_answer_from_another_thread_reaches_the_page
    run = responses
    assert_finished run
    assert_includes run.lines, "REPORT answered=from%20a%20thread", run.describe
  end

  # The drop took the request: answering it afterwards finds nothing.
  def test_a_drop_from_another_thread_releases_the_request
    run = responses
    assert_finished run
    line = run.lines.find { |l| l.start_with?("DROPPED ") }
    refute_nil line, run.describe
    assert_match(/\ADROPPED No pending request with id \d+\z/, line, run.describe)
  end

  def test_an_answer_after_the_loop_closes_fails_instead_of_hanging
    run = responses
    assert_finished run
    assert_includes run.lines, "LATE_RESPONSE Failed to send response: event loop closed", run.describe
  end

  # Tauri's request_exit and close fail with FailedToSendMessage once the
  # proxy is closed (tauri-runtime-wry lib.rs:2142-2149, 2623-2629).
  def test_exit_and_close_requests_after_the_loop_closes_fail
    run = responses
    assert_finished run
    assert_includes run.lines, "LATE_REQUEST_EXIT Failed to send exit request: event loop closed", run.describe
    assert_includes run.lines, "LATE_REQUEST_CLOSE Failed to send close request: event loop closed", run.describe
  end
end
