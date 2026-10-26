# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "json"
require "rbconfig"

# Runs a fixture app (test/integration/fixtures/*/app.rb) in a real window.
#
# Every other test drives App through StubNative. These tests open a real tao
# window with a real wry webview. tao's loop needs the main thread and ends
# the process, so the app runs in a child process, in its own process group,
# under a timeout: a hang kills the group and fails the test instead of
# blocking the suite. Without a window server the tests skip and say why.
module RealApp
  FIXTURES = File.expand_path("../fixtures", __dir__)

  # Seconds before a hung app is killed. A healthy launch takes one to two;
  # the margin is for a loaded machine, where creating the window alone can
  # take several.
  TIMEOUT = 60

  # Seconds the reader threads get to drain the pipes once the child is gone.
  DRAIN = 5

  # What one run of a fixture app left behind. +termsig+ is the signal
  # that ended it, if one did. +exit_after_signal+ is how long the app lived
  # after the +on_line+ hook last signalled it.
  Run = Data.define(:status, :termsig, :stdout, :stderr, :timed_out, :seconds, :exit_after_signal) do
    def lines
      stdout.lines(chomp: true)
    end

    # Each stdout line, with the report reduced to the word REPORT.
    def kinds
      lines.map { |line| line.start_with?("REPORT ") ? "REPORT" : line }
    end

    def report
      line = lines.find { |l| l.start_with?("REPORT ") }
      line && JSON.parse(line.delete_prefix("REPORT "))
    end

    def check(name)
      report&.fetch("checks")&.find { |check| check["name"] == name }
    end

    def describe
      "status=#{status.inspect} termsig=#{termsig.inspect} timed_out=#{timed_out} seconds=#{seconds.round(2)} " \
        "exit_after_signal=#{exit_after_signal&.round(2).inspect}\n" \
        "--- stdout\n#{stdout}\n--- stderr\n#{stderr}"
    end
  end

  # Why a real window cannot open here, or +nil+ when it can.
  def self.unavailable_reason
    case RbConfig::CONFIG["host_os"]
    when /darwin/
      session = IO.popen(["launchctl", "managername"], err: File::NULL, &:read).to_s.strip
      "no macOS GUI session (launchctl managername is #{session.inspect}, not \"Aqua\")" unless session == "Aqua"
    when /linux/
      display = [ENV["DISPLAY"], ENV["WAYLAND_DISPLAY"]].any? { |value| value && !value.empty? }
      "no display server (DISPLAY and WAYLAND_DISPLAY are unset or empty)" unless display
    when /mswin|mingw|cygwin/
      "the fixture pages build macOS and Linux URLs by hand (ipc://localhost, tokra://foreign.test); " \
        "WebView2 needs http://<scheme>.<host> forms (Plan 018, Out of scope)"
    else
      "no tao backend for #{RbConfig::CONFIG['host_os']}"
    end
  end

  # Launches fixture +name+ with +args+ and waits for it to end. +on_line+,
  # when given, sees each stdout line with the child's pid as it arrives and
  # returns +true+ when it signalled the child. A plugin passes +fixtures+,
  # its own fixture directory, and +env+, variables to add to the child's
  # environment.
  def self.launch(name, *, on_line: nil, fixtures: FIXTURES, env: {})
    started = now
    signalled_at = nil
    out_reader, out_writer = IO.pipe
    err_reader, err_writer = IO.pipe
    # The child inherits Bundler's environment, so it loads this checkout.
    pid = Process.spawn(env, RbConfig.ruby, File.join(fixtures, name, "app.rb"), *,
      out: out_writer, err: err_writer, pgroup: true)
    [out_writer, err_writer].each(&:close)
    out_thread = Thread.new do
      out_reader.each_line.with_object(+"") do |line, stdout|
        stdout << line
        signalled_at = now if on_line&.call(line, pid)
      end
    end
    err_thread = Thread.new { err_reader.read }

    waiter = Process.detach(pid)
    timed_out = waiter.join(TIMEOUT).nil?
    ended = now
    if timed_out
      kill_group(pid)
      waiter.join(DRAIN)
    end

    Run.new(
      status: waiter.alive? ? nil : waiter.value&.exitstatus,
      termsig: waiter.alive? ? nil : waiter.value&.termsig,
      stdout: drain(out_thread),
      stderr: drain(err_thread),
      timed_out:,
      seconds: ended - started,
      exit_after_signal: signalled_at && (ended - signalled_at)
    )
  ensure
    # Whatever happened above, leave no window behind.
    kill_group(pid) if pid && waiter&.alive?
    waiter&.join(DRAIN)
  end

  # Sends +signal+ to +pid+, ignoring a process that already ended.
  def self.signal(pid, signal)
    Process.kill(signal, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def self.kill_group(pid)
    signal(-pid, :KILL)
  end

  def self.drain(thread)
    thread.join(DRAIN) ? thread.value : "(stream still open after #{DRAIN} s)"
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # A Minitest base class: skips without a display, and runs each fixture
  # once per test class, however many tests read the result.
  class TestCase < Minitest::Test
    def self.fixture_run(key = :default, &launch)
      @fixture_runs ||= {}
      @fixture_runs.fetch(key) { @fixture_runs[key] = launch.call }
    end

    def setup
      reason = RealApp.unavailable_reason
      skip "real-window tests cannot run here: #{reason}" if reason
    end

    # Fails with the app's output unless it ended on its own.
    def assert_finished(run)
      refute run.timed_out, "the app hung and was killed\n#{run.describe}"
    end

    # The detail of check +name+, failing when the page never reported it.
    def check_detail(run, name)
      check = run.check(name)
      refute_nil check, "the page did not report #{name.inspect}\n#{run.describe}"
      assert check["pass"], "#{name.inspect} failed in the webview\n#{run.describe}"
      check["detail"]
    end
  end
end
