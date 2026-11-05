# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "watched_child"

# The bounds a real-window fixture runs under (Plan 060), tried against
# throwaway children that open no window: a run that keeps printing
# outlives the stall bound, one that goes quiet is killed on the first
# look past that bound, and one that prints forever is killed at the
# ceiling.
#
# These run in test:core, on a machine that may be loaded, so the bounds
# are measured on a Clock the test moves, not on the wall: what a test
# asserts is which bound tripped and in what order things happened,
# which a slow machine cannot change.
class TestWatchedChild < Minitest::Test
  # The children run without Bundler's RUBYOPT, so they start in a
  # fraction of a second even on a loaded machine.
  ENV_FOR_CHILD = { "RUBYOPT" => nil }.freeze

  # Wall-clock seconds a test waits for something that happens at once
  # when the code is right, such as a killed process going away; only a
  # broken run waits this long.
  SLACK = 20

  # The bounds below, on the test's Clock: a patience under the stall
  # bound, as WatchedChild.run requires, and a ceiling none reaches.
  BOUNDS = { patience: 1, stall: 2, ceiling: 1000 }.freeze

  # A clock the test moves. Each read moves it +step+ seconds once
  # +moving+ is set, and #advance moves it at once. Reads come from the
  # watching thread and the stdout reader alike.
  class Clock
    attr_writer :moving

    def initialize(step: 0)
      @now = 0.0
      @step = step
      @moving = false
      @lock = Mutex.new
    end

    def call
      @lock.synchronize do
        @now += @step if @moving
        @now
      end
    end

    def advance(seconds)
      @lock.synchronize { @now += seconds }
    end
  end

  def ruby(script)
    [RbConfig.ruby, "--disable-gems", "-e", "$stdout.sync = true\n#{script}"]
  end

  def run_child(script, **, &)
    WatchedChild.run(ENV_FOR_CHILD, ruby(script), **, &)
  end

  # Whether +pid+ is gone, or on POSIX only a zombie, which a SIGKILL
  # leaves until its parent reaps it; waits up to SLACK seconds for that.
  def ended?(pid)
    deadline = WatchedChild.now + SLACK
    loop do
      return true unless running?(pid)
      return false if WatchedChild.now > deadline

      sleep 0.05
    end
  end

  # Whether +pid+ is a running process. On Windows, tasklist lists only
  # running processes, and with /FO CSV quotes each pid.
  def running?(pid)
    if WatchedChild.windows?
      listed = IO.popen(["tasklist", "/FI", "PID eq #{pid}", "/NH", "/FO", "CSV"], err: File::NULL, &:read)
      listed.include?("\"#{pid}\"")
    else
      state = IO.popen(["ps", "-o", "stat=", "-p", pid.to_s], err: File::NULL, &:read).strip
      !state.empty? && !state.start_with?("Z")
    end
  end

  # Asserts that a child with +termsig+ and +exitstatus+ was killed, as
  # this platform reports a kill. On POSIX that is SIGKILL's termsig.
  # Windows has no signals: Ruby's waitpid reports a process's exit code
  # as its status, and a signal only for an NTSTATUS failure code
  # (poll_child_status in Ruby 4.0.9's win32/win32.c), and WatchedChild
  # kills through taskkill, which chooses the exit code itself. So there
  # the child must have ended with an exit code and no signal; each test
  # runs a child that would not end on its own.
  def assert_killed(termsig, exitstatus, message = nil)
    if WatchedChild.windows?
      assert_nil termsig, message
      refute_nil exitstatus, "the child did not end\n#{message}"
    else
      assert_equal Signal.list.fetch("KILL"), termsig, message
    end
  end

  # Each line moves the clock 1.5 s, under the 2 s stall bound, eight
  # times, so only each new line keeps the child alive.
  def test_a_child_that_keeps_printing_outlives_the_stall_bound
    clock = Clock.new
    outcome = run_child("8.times { |i| puts \"tick \#{i}\"; sleep 0.02 }", **BOUNDS, clock:, on_line: lambda { |_line, _pid|
      clock.advance(1.5)
      false
    })

    assert_nil outcome.bound, outcome.inspect
    assert_equal 0, outcome.status, outcome.inspect
    assert_operator outcome.seconds, :>, BOUNDS[:stall], "the child ended before the stall bound, so it proves nothing"
    assert_equal (0..7).map { |i| "tick #{i}\n" }.join, outcome.stdout
    assert_equal "tick 7", outcome.last_line
    assert_nil outcome.verdict
  end

  # Once the line is in, each look moves the clock a quarter second, so
  # the look that trips the bound is the first past it.
  def test_a_child_that_goes_quiet_is_killed_on_the_first_look_past_the_stall_bound
    clock = Clock.new(step: 0.25)
    pids = []
    outcome = run_child("puts 'only line'; sleep 600", **BOUNDS, clock:,
      on_line: lambda { |_line, _pid|
        clock.moving = true
        false
      },
      on_hang: lambda { |pid|
        pids << pid
        "probed"
      })

    assert_equal :stall, outcome.bound, outcome.inspect
    assert outcome.timed_out
    assert_equal "only line", outcome.last_line
    assert_operator outcome.quiet_for, :>, BOUNDS[:stall], outcome.inspect
    assert_operator outcome.quiet_for, :<=, BOUNDS[:stall] + 0.25, outcome.inspect
    assert_killed outcome.termsig, outcome.status, outcome.inspect
    assert_equal "probed", outcome.probe
    assert_equal 1, pids.size
    assert_match(/\Ano progress: no new line for \d+\.\d s, and its last line was "only line"\z/, outcome.verdict)
  end

  # The outcome describes the run as the bound saw it: a line the child
  # prints while on_hang probes, and the time the probe takes, change
  # neither its last line nor how long it was quiet. The probe asks for
  # the line by creating a file the child waits for, not by a signal,
  # which Windows could not send.
  def test_a_tripped_bound_is_described_as_it_was_when_it_tripped
    clock = Clock.new(step: 0.25)
    late = Thread::Queue.new
    cue = File.join(Dir.mktmpdir("watched-child"), "cue")
    outcome = run_child("puts 'only line'; sleep 0.01 until File.exist?(#{cue.inspect}); puts 'late line'; sleep 600",
      **BOUNDS, clock:,
      on_line: lambda { |line, _pid|
        clock.moving = true
        late << line if line == "late line\n"
        false
      },
      on_hang: lambda { |_pid|
        File.write(cue, "")
        heard = late.pop(timeout: SLACK)
        clock.advance(100)
        heard
      })

    assert_equal "late line\n", outcome.probe, "the child never printed its late line\n#{outcome.inspect}"
    assert_equal :stall, outcome.bound, outcome.inspect
    assert_equal "only line", outcome.last_line, outcome.inspect
    assert_operator outcome.quiet_for, :<=, BOUNDS[:stall] + 0.25, outcome.inspect
    assert_includes outcome.stdout, "late line"
  ensure
    FileUtils.rm_rf(File.dirname(cue)) if cue
  end

  # Stderr is not progress: a library can log there while the app is
  # stuck. The child logs far more often than the bounds are looked at.
  def test_lines_on_stderr_do_not_count_as_progress
    clock = Clock.new(step: 0.25)
    outcome = run_child("warn 'noise'; puts 'only line'; 400.times { warn 'noise'; sleep 0.05 }", **BOUNDS, clock:,
      on_line: lambda { |_line, _pid|
        clock.moving = true
        false
      })

    assert_equal :stall, outcome.bound, outcome.inspect
    assert_includes outcome.stderr, "noise"
  end

  def test_a_child_that_prints_no_line_is_killed_at_the_stall_bound
    clock = Clock.new(step: 0.25)
    clock.moving = true
    outcome = run_child("sleep 600", **BOUNDS, clock:)

    assert_equal :stall, outcome.bound, outcome.inspect
    assert_nil outcome.last_line
    assert_match(/, and it printed no line\z/, outcome.verdict)
  end

  # Each read moves the clock a little, and the child prints far more
  # often than that adds up to the stall bound, so only the ceiling can
  # end it. It prints for about 20 seconds and then ends on its own, so a
  # run without the ceiling ends with no bound rather than hanging.
  def test_a_child_that_keeps_printing_is_killed_at_the_ceiling
    clock = Clock.new(step: 0.05)
    clock.moving = true
    outcome = run_child("1000.times { |i| puts \"tick \#{i}\"; sleep 0.02 }", **BOUNDS.merge(ceiling: 4), clock:)

    assert_equal :ceiling, outcome.bound, outcome.inspect
    assert_operator outcome.seconds, :>, 4, outcome.inspect
    assert_operator outcome.quiet_for, :<=, BOUNDS[:stall], "the child was still printing\n#{outcome.inspect}"
    assert_killed outcome.termsig, outcome.status, outcome.inspect
    assert_match(/\Apast the ceiling: still running after \d+\.\d s, and its last line was "tick \d+"\z/,
      outcome.verdict)
  end

  # A child that ends just as a bound trips was not hung. Here the first
  # look after its line crosses the stall bound, and the clock answers
  # only once the child has ended, the way a child can end between the
  # watcher's wait and its look at the bounds.
  def test_a_child_that_ends_as_a_bound_trips_is_not_killed
    clock = Clock.new(step: 3)
    watched = nil
    crossing = lambda do
      now = clock.call
      watched&.join(SLACK) if now > BOUNDS[:stall]
      now
    end
    outcome = run_child("puts 'only line'; sleep 1", **BOUNDS, clock: crossing,
      on_line: lambda { |_line, _pid|
        clock.moving = true
        false
      }) { |_pid, waiter| watched = waiter }

    assert_nil outcome.bound, outcome.inspect
    assert_equal 0, outcome.status, outcome.inspect
  end

  # The kill is the group's, or on Windows the process tree's, so what
  # the child started goes with it.
  def test_a_tripped_bound_kills_what_the_child_started
    clock = Clock.new(step: 0.25)
    grandchild = nil
    sleeper = [RbConfig.ruby, "--disable-gems", "-e", "sleep 600"]
    outcome = run_child("puts Process.spawn(*#{sleeper.inspect}); sleep 600", **BOUNDS, clock:,
      on_line: lambda { |line, _pid|
        grandchild = Integer(line)
        clock.moving = true
        false
      })

    assert_equal :stall, outcome.bound, outcome.inspect
    refute_nil grandchild, outcome.inspect
    assert ended?(grandchild), "the child's own child #{grandchild} outlived the kill"
  ensure
    WatchedChild.signal(grandchild, :KILL) if grandchild
  end

  # A probe that raises still leaves no child behind.
  def test_a_raising_probe_still_kills_and_reaps_the_child
    clock = Clock.new(step: 0.25)
    clock.moving = true
    watched = nil
    error = assert_raises(RuntimeError) do
      run_child("sleep 600", **BOUNDS, clock:, on_hang: -> (_pid) { raise "the probe broke" }) do |_pid, waiter|
        watched = waiter
      end
    end

    assert_equal "the probe broke", error.message
    refute watched.alive?, "the child outlived the error"
    assert_killed watched.value.termsig, watched.value.exitstatus
  end

  def test_a_raising_block_still_kills_and_reaps_the_child
    watched = nil
    error = assert_raises(RuntimeError) do
      run_child("sleep 600") do |_pid, waiter|
        watched = waiter
        raise "the watcher broke"
      end
    end

    assert_equal "the watcher broke", error.message
    refute watched.alive?, "the child outlived the error"
    assert_killed watched.value.termsig, watched.value.exitstatus
  end

  # The child is told its patience, whatever +env+ says.
  def test_the_child_learns_its_patience
    outcome = WatchedChild.run(ENV_FOR_CHILD.merge(WatchedChild::PATIENCE_VARIABLE => "99"),
      ruby("puts ENV.fetch(#{WatchedChild::PATIENCE_VARIABLE.inspect})"), patience: 1.5, stall: 2)

    assert_equal "1.5", outcome.last_line, outcome.inspect
  end

  # Unless told otherwise, the stall bound is the patience and MARGIN,
  # so a child that gives up on a wait has time to say so.
  def test_the_stall_bound_is_the_patience_and_the_margin
    clock = Clock.new(step: 8)
    clock.moving = true
    outcome = run_child("sleep 600", patience: 1, ceiling: 1000, clock:)

    assert_equal :stall, outcome.bound, outcome.inspect
    assert_operator outcome.quiet_for, :>, 1 + WatchedChild::MARGIN, outcome.inspect
    assert_operator outcome.quiet_for, :<=, 1 + WatchedChild::MARGIN + 8, outcome.inspect
    assert_equal WatchedChild::PATIENCE + WatchedChild::MARGIN, WatchedChild::STALL
  end

  def test_a_stall_bound_no_longer_than_the_patience_is_refused
    error = assert_raises(ArgumentError) { run_child("exit", patience: 2, stall: 2) }

    assert_equal "the stall bound (2 s) must be longer than the child's patience (2 s)", error.message
  end

  # +on_line+ sees each line with the pid, and the outcome says how long
  # the child lived after the hook last signalled it. Windows sends only
  # KILL, INT, and 0; Ruby's KILL there is TerminateProcess(hProc, 0),
  # so the child reports exit code 0 and no signal (kill and
  # poll_child_status in Ruby 4.0.9's win32/win32.c).
  def test_on_line_can_signal_the_child_and_the_outcome_times_its_end
    signal = WatchedChild.windows? ? :KILL : :TERM
    outcome = run_child("puts 'READY'; sleep 600", on_line: lambda { |line, pid|
      line == "READY\n" && WatchedChild.signal(pid, signal)
    })

    assert_nil outcome.bound, outcome.inspect
    if WatchedChild.windows?
      assert_nil outcome.termsig, outcome.inspect
      assert_equal 0, outcome.status, outcome.inspect
    else
      assert_equal Signal.list.fetch("TERM"), outcome.termsig, outcome.inspect
    end
    refute_nil outcome.exit_after_signal
    assert_operator outcome.exit_after_signal, :>=, 0, outcome.inspect
  end

  def test_the_block_gets_the_pid_and_the_waiter_after_the_spawn
    seen = nil
    outcome = run_child("puts $$") { |pid, waiter| seen = [pid, waiter.pid] }

    assert_equal [Integer(outcome.last_line)] * 2, seen
  end

  # Progress resets the stall bound, never the ceiling, which RestartTest
  # relies on for the runs its fixture restarts.
  def test_bounds_progress_resets_the_stall_bound_but_not_the_ceiling
    now = 0.0
    bounds = WatchedChild::Bounds.new(stall: 2, ceiling: 5, clock: -> { now })

    now = 1.5
    assert_nil bounds.check.bound
    now = 2.5
    assert_equal :stall, bounds.check.bound
    bounds.progress("moved")
    assert_nil bounds.check.bound
    now = 4.0
    bounds.progress
    now = 5.5
    reading = bounds.check

    assert_equal :ceiling, reading.bound
    assert_in_delta 1.5, reading.quiet_for
    assert_in_delta 5.5, reading.seconds
    assert_nil reading.progress.line
  end
end
