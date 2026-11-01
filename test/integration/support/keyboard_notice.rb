# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Keeps tests that take a Mac's keyboard and mouse out of each other's
# way, and tells the person at the Mac, aloud, when to step away and when
# to come back.
#
# Some real-window tests must open a real menu, which tracks the keyboard
# and mouse until it closes, or must bring a fixture to the front. They
# stay reliable only if nobody types into them, and only if no other
# project's tests on the same Mac take the keyboard at the same time.
# Wrapping each in KeyboardNotice.taking_the_keyboard holds a lock that
# every such project shares, says "step away" before the first, and says
# "you can come back" once SETTLE seconds pass with none running, so a run
# of such tests is announced once and the person is called back as soon
# as it ends rather than when the whole gate does.
#
# The lock and the spoken notice follow a protocol agreed with the other
# projects whose tests share the Mac (Plan 046):
#
# - The lock is an exclusive +flock+ on LOCK_PATH, held only while a
#   block runs, so the system frees it if the process dies.
# - Whoever takes the lock and finds no marker at MARKER_PATH, or one
#   naming a process that has ended, writes its own and says STEP_AWAY.
#   A marker naming a live process means someone has already warned.
# - Once SETTLE seconds pass with none of its blocks running, a process
#   tries the lock without waiting. If it gets it and the marker is
#   there, it removes the marker and says COME_BACK. If the lock is
#   busy, someone else is still working, and will call the person back.
#
# The lock is taken on macOS unless CI is set, even when quiet, since its
# purpose is that two projects' tests never collide. Speaking needs
# macOS's own +say+, and stops when DESKTOP_INPUT_QUIET or TOKRA_QUIET is
# set.
#
# === Example
#
#   KeyboardNotice.taking_the_keyboard { menu.popup(window) }
module KeyboardNotice
  STEP_AWAY = "Tests need the keyboard and mouse for a moment. Please step away."
  COME_BACK = "The tests are done with the keyboard and mouse. You can come back now."

  # The line written to standard error while another process holds the lock.
  WAITING = "waiting for the desktop input lock"

  # The lock every project's keyboard-taking tests share. Literally +/tmp+,
  # not Dir.tmpdir, which differs between processes on macOS.
  LOCK_PATH = "/tmp/desktop-input.lock"

  # The marker that says the person was told to step away: "<pid> <unix
  # time>" of the process that told them.
  MARKER_PATH = "/tmp/desktop-input.away"

  # How long, in seconds, no keyboard-taking block may run before the
  # person is called back. Long enough to bridge the gap between two such
  # tests in a row, short enough that nobody waits on an idle gate.
  SETTLE = 3

  # One process's share of the desk: its hold on the lock, the marker, and
  # the watcher that calls the person back. Blocks nest, and blocks on
  # other threads of the same process share the one lock held while any
  # runs. Its watcher is a thread polling #tick; <tt>watcher: false</tt> leaves
  # the polls to the caller, and +clock+ replaces the monotonic clock.
  class Desk
    # Reads the monotonic clock, in seconds.
    CLOCK = -> { ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) }

    # Speaks +words+ with macOS's +say+, waiting until they are said.
    SAY = -> (words) { system("/usr/bin/say", words, exception: false) }

    def initialize(lock_path: LOCK_PATH, marker_path: MARKER_PATH, settle: SETTLE, voice: SAY, err: $stderr,
      clock: CLOCK, watcher: true
    )
      @lock_path = lock_path
      @marker_path = marker_path
      @settle = settle
      @voice = voice
      @err = err
      @clock = clock
      @watches = watcher
      @mutex = Mutex.new
      @depth = 0
      @lock = nil
      @pending = false
      @last_done = nil
      @watcher = nil
    end

    # Runs the block holding the lock, and returns its value. With
    # +speak+, first says STEP_AWAY unless the person was already told, and
    # afterwards says COME_BACK once nothing has taken the keyboard for
    # SETTLE seconds. Without +speak+, never speaks and never touches the
    # marker. Without a block it only takes the lock and announces.
    def taking_the_keyboard(speak: true)
      enter(speak)
      begin
        block_given? ? yield : nil
      ensure
        leave
      end
    end

    # Calls the person back if nobody holds the lock and the marker says
    # they were sent away. Never waits for the lock.
    def call_back
      @mutex.synchronize { come_back }
    end

    # Stops the watcher.
    def stop
      @watcher&.kill&.join
      @watcher = nil
    end

    private def enter(speak)
      @mutex.synchronize do
        acquire if @depth.zero?
        @depth += 1
        next unless speak

        step_away unless live_marker?
        @pending = true
        @watcher ||= Thread.new { watch } if @watches
      end
    end

    private def leave
      @mutex.synchronize do
        @depth -= 1
        @last_done = @clock.call
        release if @depth.zero?
      end
    end

    private def acquire
      file = open_lock
      begin
        unless file.flock(File::LOCK_EX | File::LOCK_NB)
          @err.puts(WAITING)
          file.flock(File::LOCK_EX)
        end
      rescue Exception
        file.close
        raise
      end
      @lock = file
    end

    private def release
      @lock&.close
      @lock = nil
    end

    private def open_lock
      File.open(@lock_path, File::RDONLY | File::CREAT, 0o666)
    end

    private def step_away
      File.write(@marker_path, "#{::Process.pid} #{Time.now.to_i}")
      @voice.call(STEP_AWAY)
    end

    private def live_marker?
      pid = Integer(File.read(@marker_path).split.first, exception: false)
      !pid.nil? && pid.positive? && alive?(pid)
    rescue Errno::ENOENT
      false
    end

    private def alive?(pid)
      ::Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # What the watcher does on each poll: once a speaking span has run and
    # none has for SETTLE seconds, calls the person back, once.
    def tick
      @mutex.synchronize do
        next unless @pending && @depth.zero?
        next if @clock.call - @last_done < @settle

        @pending = false
        come_back
      end
    end

    private def watch
      loop do
        sleep [@settle / 4.0, 0.25].min
        tick
      end
    end

    private def come_back
      File.open(@lock_path, File::RDONLY | File::CREAT, 0o666) do |file|
        next unless file.flock(File::LOCK_EX | File::LOCK_NB)
        next unless File.exist?(@marker_path)

        File.delete(@marker_path)
        @voice.call(COME_BACK)
      end
    end
  end

  class << self
    # Runs the block holding the shared lock, where #locks?, and returns
    # its value; see Desk#taking_the_keyboard. It speaks only where
    # #speaks?, and never with <tt>speak: false</tt>.
    def taking_the_keyboard(speak: true, &)
      return (block_given? ? yield : nil) unless locks?

      speaking = speak && speaks?
      call_back_at_exit if speaking
      desk.taking_the_keyboard(speak: speaking, &)
    end

    # Whether tests on this machine may collide with another project's over
    # the keyboard: macOS, not CI.
    def locks?
      RbConfig::CONFIG["host_os"].include?("darwin") && !ENV["CI"]
    end

    # Whether this machine is one a person may be typing at: it locks, has
    # +say+, and is silenced by neither DESKTOP_INPUT_QUIET nor TOKRA_QUIET.
    def speaks?
      locks? && !ENV["DESKTOP_INPUT_QUIET"] && !ENV["TOKRA_QUIET"] && File.executable?("/usr/bin/say")
    end

    # This process's Desk, on the shared paths.
    def desk
      @desk ||= Desk.new
    end

    private def call_back_at_exit
      return if @calling_back

      @calling_back = true
      at_exit do
        desk.stop
        desk.call_back
      end
    end
  end
end
