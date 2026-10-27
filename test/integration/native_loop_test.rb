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
end
