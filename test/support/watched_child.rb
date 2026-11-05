# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# Runs a child process in its own process group, collects what it prints,
# and kills the group, or on Windows the process tree, once it stops
# making progress (Plan 060).
#
# A fixed limit from the launch turns a slow run into a hang: at a load
# near 400, RealApp's 60 seconds killed a fixture whose page was two
# thirds through its checks. So the child is held to two bounds instead.
# +stall+ is how long it may go without printing a line to stdout: each
# line a fixture prints says the thing under test moved, so a run that
# goes quiet for that long is hung, however long it ran before. +ceiling+
# is how long it may run at all, for a run that keeps printing but never
# ends. Neither counts stderr, where a library may log on its own while
# the app is stuck.
#
# The child also learns its +patience+, in TOKRA_FIXTURE_PATIENCE: how
# long any one of its own waits may last before it gives up and says
# what it was waiting for. The stall bound is longer by MARGIN, so a
# child that gives up on a hung wait has time to say so before it is
# killed, even on a loaded machine, and the failure names the wait
# rather than only the child's last line.
#
# The real-window fixtures launch through RealApp.launch, never through
# this directly: RealApp checks the tripwire (RealWindowsRun) before it
# calls this, and this checks nothing. Nothing here opens a window, so
# its own tests run in test:core.
#
# === Example
#
#   outcome = WatchedChild.run({}, [RbConfig.ruby, "-e", "puts :hi"])
#   outcome.bound   #=> nil
#   outcome.stdout  #=> "hi\n"
module WatchedChild
  # Seconds one of the child's own waits may last: each check of a
  # fixture's page, and each wait for an event inside a fixture. A healthy
  # check takes about a second idle, and about nine at a load near 400.
  PATIENCE = 60

  # Seconds the stall bound gives a child past its patience: time for a
  # wait that gave up to reach stdout through a loaded machine.
  MARGIN = 30

  # Seconds with no new line on stdout before a child counts as hung.
  STALL = PATIENCE + MARGIN

  # Seconds a child may run, however much it prints.
  CEILING = 15 * 60

  # The variable that tells the child its patience, in seconds.
  PATIENCE_VARIABLE = "TOKRA_FIXTURE_PATIENCE"

  # Seconds the reader threads get to drain the pipes once the child is
  # gone.
  DRAIN = 5

  # The longest wait, in seconds, between two looks at the bounds.
  POLL = 1

  # Why a run was killed, for Outcome and RealApp::Run alike: +bound+
  # (+:stall+, +:ceiling+, or +nil+), +quiet_for+, the seconds since its
  # last stdout line when it ended or a bound tripped, +seconds+, and
  # +last_line+.
  module Verdict
    # Whether a bound tripped and the child was killed.
    def timed_out
      !bound.nil?
    end

    # Which bound tripped, in words, with the last line the child printed;
    # +nil+ when none did.
    def verdict
      seen = last_line ? "its last line was #{last_line.inspect}" : "it printed no line"
      case bound
      when :stall then "no progress: no new line for #{quiet_for.round(1)} s, and #{seen}"
      when :ceiling then "past the ceiling: still running after #{seconds.round(1)} s, and #{seen}"
      end
    end
  end

  # What one run left behind. +termsig+ is the signal that ended it, if
  # one did. Windows has no signals, so there +termsig+ stays +nil+ and a
  # killed child reports an exit code as its +status+: 0 for Ruby's own
  # Process.kill(:KILL), whatever taskkill chose for a tripped bound's
  # kill (kill_group). +exit_after_signal+ is how long it lived after +on_line+
  # last signalled it. +probe+ is what +on_hang+ answered before the
  # kill, or +nil+.
  Outcome = Data.define(:status, :termsig, :stdout, :stderr, :bound, :seconds, :quiet_for, :last_line,
    :exit_after_signal, :probe) do
    include Verdict
  end

  # The last progress a run made: +at+, when, on its clock, and +line+,
  # the stdout line it printed then, or +nil+ for its start.
  Progress = Data.define(:at, :line)

  # One look at a run's bounds: +bound+, the one that had tripped, or
  # +nil+; +now+, when the look was taken; +started+, when the run began;
  # and +progress+, the last Progress it had seen.
  Reading = Data.define(:bound, :now, :started, :progress) do
    # Seconds since the last progress.
    def quiet_for
      now - progress.at
    end

    # Seconds since the start.
    def seconds
      now - started
    end
  end

  # The stall and ceiling bounds over one run, read on +clock+, which
  # answers seconds. The run's start counts as its first progress.
  # WatchedChild.run holds a child to them, and a test that waits on
  # anything else that should keep moving, such as RestartTest on the
  # runs its fixture restarts, can hold that to them too.
  #
  #   bounds = WatchedChild::Bounds.new(stall: 90, ceiling: 900)
  #   bounds.progress("a line")
  #   bounds.check.bound  #=> nil
  class Bounds
    def initialize(stall:, ceiling:, clock: WatchedChild.method(:now))
      @stall = stall
      @ceiling = ceiling
      @clock = clock
      @started = clock.call
      @progress = Progress.new(at: @started, line: nil)
    end

    # Records progress now, with the +line+ that showed it. Another
    # thread may call this while one checks: each sees a whole Progress.
    def progress(line = nil)
      @progress = Progress.new(at: @clock.call, line:)
    end

    # A Reading taken now, naming the ceiling if the run has outlived it,
    # else the stall bound if it has gone that long without progress.
    def check
      seen = @progress
      now = @clock.call
      bound = if now - @started > @ceiling then :ceiling elsif now - seen.at > @stall then :stall end
      Reading.new(bound:, now:, started: @started, progress: seen)
    end
  end

  # Runs +command+ (an argv array) with +env+ added to the environment,
  # in a process group of its own, and waits until it ends or a bound
  # trips, which kills it and what it started (kill_group). +patience+
  # goes to the child in PATIENCE_VARIABLE, over any
  # value +env+ gives, and +stall+ must be longer. +clock+ answers the
  # seconds every bound and duration is measured on. +on_line+, when
  # given, sees each stdout line with the child's pid as it arrives and
  # returns +true+ when it signalled the child. Once a bound trips,
  # +on_hang+, when given, sees the pid before the group is killed, and
  # what it answers becomes the outcome's +probe+. The block, when given,
  # gets the pid and the Process.detach thread right after the spawn, to
  # watch the child alongside. +drain+ is how many seconds the readers
  # get to finish once the child is gone. If anything here raises, the
  # group is killed and the child reaped before the error goes on.
  def self.run(env, command, patience: PATIENCE, stall: patience + MARGIN, ceiling: CEILING, drain: DRAIN,
    clock: method(:now), on_line: nil, on_hang: nil
  )
    unless stall > patience
      raise ArgumentError, "the stall bound (#{stall} s) must be longer than the child's patience (#{patience} s)"
    end

    bounds = Bounds.new(stall:, ceiling:, clock:)
    signalled_at = nil
    out_reader, out_writer = IO.pipe
    err_reader, err_writer = IO.pipe
    group = windows? ? { new_pgroup: true } : { pgroup: true }
    pid = ::Process.spawn(env.merge(PATIENCE_VARIABLE => patience.to_s), *command, out: out_writer, err: err_writer,
      **group)
    [out_writer, err_writer].each(&:close)
    # The readers fill buffers this thread owns, so a stream still open
    # after the kill still shows what arrived, such as a fixture's last
    # PROGRESS line.
    stdout = +""
    stderr = +""
    out_thread = Thread.new do
      out_reader.each_line do |line|
        bounds.progress(line.chomp)
        stdout << line
        signalled_at = clock.call if on_line&.call(line, pid)
      end
    end
    err_thread = Thread.new { err_reader.each_line { |line| stderr << line } }

    waiter = ::Process.detach(pid)
    yield pid, waiter if block_given?
    tripped = watch(waiter, bounds, [POLL, stall / 4.0].min)
    if tripped
      probe = on_hang&.call(pid)
      kill_group(pid)
      waiter.join(drain)
    end
    out = self.drain(out_thread, stdout, drain)
    err = self.drain(err_thread, stderr, drain)
    # A killed run is described as the bound saw it; one that ended, once
    # its last lines are read.
    reading = tripped || bounds.check

    Outcome.new(
      status: waiter.alive? ? nil : waiter.value&.exitstatus,
      termsig: waiter.alive? ? nil : waiter.value&.termsig,
      stdout: out,
      stderr: err,
      bound: tripped&.bound,
      seconds: reading.seconds,
      quiet_for: reading.quiet_for,
      last_line: reading.progress.line,
      exit_after_signal: signalled_at && (reading.now - signalled_at),
      probe:
    )
  ensure
    # Whatever happened above, leave nothing of the child behind.
    kill_group(pid) if pid && waiter&.alive?
    waiter&.join(drain)
  end

  # Waits, looking every +poll+ seconds, until +waiter+'s child ends,
  # and answers +nil+, or until one of +bounds+ trips while it still
  # runs, and answers that Reading.
  def self.watch(waiter, bounds, poll)
    until waiter.join(poll)
      reading = bounds.check
      next unless reading.bound
      # The child may have ended since the join gave up on it.
      return nil if waiter.join(0)

      return reading
    end
    nil
  end

  # Sends +signal+ to +pid+, ignoring a process that already ended. On
  # Windows Ruby sends only +:KILL+, which is TerminateProcess with exit
  # code 0, +:INT+, which is a CTRL_BREAK_EVENT to the process's group,
  # and 0; any other signal, or a negative pid, raises Errno::EINVAL
  # (kill in Ruby 4.0.9's win32/win32.c).
  def self.signal(pid, signal)
    ::Process.kill(signal, pid)
    true
  rescue Errno::ESRCH
    false
  end

  # Kills the child's process group, and so whatever the child started.
  # Windows has no process groups to signal, and killing a process there
  # leaves its children running, as WebView2's browser processes would
  # be. So there taskkill ends the child's tree: /T takes every process
  # the child started, and theirs, and /F terminates rather than asks.
  # Should taskkill fail, the child itself is still killed. Until Ruby
  # reaps the child it holds the child's process handle, which keeps the
  # pid from naming another process, so only a child that ended and was
  # reaped just before the kill leaves a window for that, as on POSIX.
  def self.kill_group(pid)
    return signal(-pid, :KILL) unless windows?

    signal(pid, :KILL) unless system("taskkill", "/T", "/F", "/PID", pid.to_s, out: File::NULL, err: File::NULL)
  end

  def self.windows?
    RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
  end

  # What +thread+ read into +buffer+, once it has read the whole stream
  # or +wait+ seconds pass; then with a note that the stream is still open.
  def self.drain(thread, buffer, wait = DRAIN)
    thread.join(wait) ? buffer.dup : "#{buffer}(stream still open after #{wait} s)"
  end

  def self.now
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end
end
