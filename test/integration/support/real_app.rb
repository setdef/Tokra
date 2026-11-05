# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "json"
require "rbconfig"
require_relative "frontmost"
require_relative "hang_probe"
require_relative "../../support/real_windows_run"
require_relative "../../support/watched_child"

# Runs a fixture app (test/integration/fixtures/*/app.rb) in a real window.
#
# Every other test drives App through StubNative. These tests open a real tao
# window with a real wry webview. tao's loop needs the main thread and ends
# the process, so the app runs in a child process, in its own process group,
# under WatchedChild's bounds: a fixture that stops printing, or never
# ends, has its group killed, or on Windows its process tree, and fails
# the test instead of blocking the suite, and a slow one still passes. Without a window server the tests
# skip and say why.
#
# On macOS every fixture runs in the background (FixtureApp.background), so
# the suite never takes the keyboard from the person at the machine, and
# RealApp watches the frontmost app to hold every fixture to that.
module RealApp
  FIXTURES = File.expand_path("../fixtures", __dir__)

  # Seconds one of a fixture's own waits may last: each check of its page
  # (harness.js) and each wait for an event in its Ruby. The fixture
  # reads it as FixtureApp::PATIENCE.
  PATIENCE = WatchedChild::PATIENCE

  # Seconds a fixture may go without printing a line before it counts as
  # hung (WatchedChild): its patience and WatchedChild::MARGIN, so a wait
  # that gave up reports before the kill. Each line says the app moved:
  # the fixture's loaded line, the start and end of each page check, and
  # its own contract lines.
  STALL = WatchedChild::STALL

  # Seconds a fixture may run at all, for one that keeps printing but
  # never ends.
  CEILING = WatchedChild::CEILING

  # Seconds the reader threads get to drain the pipes once the child is gone.
  DRAIN = WatchedChild::DRAIN

  # Seconds between looks at the frontmost app.
  WATCH = 0.05

  # What one run of a fixture app left behind: WatchedChild::Outcome's
  # fields, and +activated+, whether the app was ever the frontmost app,
  # or +nil+ where Frontmost cannot tell. +probe+ is what HangProbe found
  # about an app that hung, before the kill, or +nil+.
  Run = Data.define(*WatchedChild::Outcome.members, :activated) do
    include WatchedChild::Verdict

    # Each stdout line but the PROGRESS lines, which say how far the
    # fixture got, not what it found.
    def lines
      stdout.lines(chomp: true).grep_v(/\APROGRESS /)
    end

    # The PROGRESS lines, in order.
    def progress
      stdout.lines(chomp: true).grep(/\APROGRESS /)
    end

    # Each line, with the report reduced to the word REPORT.
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
      "#{"#{verdict}\n" if verdict}" \
        "status=#{status.inspect} termsig=#{termsig.inspect} timed_out=#{timed_out} seconds=#{seconds.round(2)} " \
        "exit_after_signal=#{exit_after_signal&.round(2).inspect} activated=#{activated.inspect}\n" \
        "--- stdout\n#{stdout}\n--- stderr\n#{stderr}#{"\n--- probe\n#{probe}" if probe}"
    end
  end

  # Why a real window cannot open here, or +nil+ when it can. A fixture
  # that loads no page (+page+ false) runs on Windows too.
  def self.unavailable_reason(page: true)
    case RbConfig::CONFIG["host_os"]
    when /darwin/
      session = IO.popen(["launchctl", "managername"], err: File::NULL, &:read).to_s.strip
      "no macOS GUI session (launchctl managername is #{session.inspect}, not \"Aqua\")" unless session == "Aqua"
    when /linux/
      display = [ENV["DISPLAY"], ENV["WAYLAND_DISPLAY"]].any? { |value| value && !value.empty? }
      "no display server (DISPLAY and WAYLAND_DISPLAY are unset or empty)" unless display
    when /mswin|mingw|cygwin/
      return nil unless page

      "the fixture pages build macOS and Linux URLs by hand (ipc://localhost, tokra://foreign.test); " \
        "WebView2 needs http://<scheme>.<host> forms (Plan 018, Out of scope)"
    else
      "no tao backend for #{RbConfig::CONFIG['host_os']}"
    end
  end

  # Launches fixture +name+ with +args+ and waits for it to end, or to go
  # the stall bound without a line, or to run +ceiling+ seconds, which
  # kill it (WatchedChild). +patience+ is the fixture's, and the stall
  # bound is WatchedChild::MARGIN longer. +on_line+, when given, sees each stdout line
  # with the child's pid as it arrives and returns +true+ when it
  # signalled the child. A plugin passes +fixtures+, its own fixture
  # directory, and +env+, variables to add to the child's environment.
  # +drain+ is how many seconds the readers get to finish once the child
  # is gone.
  def self.launch(name, *, on_line: nil, fixtures: FIXTURES, env: {}, drain: DRAIN, patience: PATIENCE,
    ceiling: CEILING
  )
    RealWindowsRun.require!("RealApp.launch(#{name.inspect})")
    # The child inherits Bundler's environment, so it loads this checkout.
    command = [RbConfig.ruby, File.join(fixtures, name, "app.rb"), *]
    watcher = nil
    outcome = WatchedChild.run(env, command, patience:, ceiling:, drain:, on_line:,
      on_hang: HangProbe.method(:call)) { |pid, waiter| watcher = watch_front(pid, waiter) }
    Run.new(**outcome.to_h, activated: watcher&.value)
  end

  # A thread that answers whether +pid+ was ever the frontmost app while
  # +waiter+ was alive, or +nil+ where Frontmost cannot tell. Where it
  # cannot, the guard is silent, so it is never the only protection: a
  # fixture keeps the Prohibited activation policy and shows nothing that
  # activates the app, such as an NSAlert sheet (plan 035).
  def self.watch_front(pid, waiter)
    return nil unless Frontmost.available?

    Thread.new do
      activated = false
      while waiter.alive?
        activated ||= Frontmost.pid == pid
        sleep WATCH
      end
      activated
    end
  end

  # Sends +signal+ to +pid+, ignoring a process that already ended; on
  # Windows only +:KILL+, +:INT+, and 0 (WatchedChild.signal).
  def self.signal(pid, signal)
    WatchedChild.signal(pid, signal)
  end

  def self.windows?
    WatchedChild.windows?
  end

  # What +thread+ read into +buffer+, once it has read the whole stream
  # or +wait+ seconds pass; then with a note that the stream is still open.
  def self.drain(thread, buffer, wait = DRAIN)
    WatchedChild.drain(thread, buffer, wait)
  end

  def self.now
    WatchedChild.now
  end

  # A Minitest base class: skips without a display, and runs each fixture
  # once per test class, however many tests read the result.
  class TestCase < Minitest::Test
    # Whether the fixtures this class launches load a page. Those that do
    # not run on Windows too.
    def self.page?
      true
    end

    def self.fixture_run(key = :default, &launch)
      @fixture_runs ||= {}
      @fixture_runs.fetch(key) { @fixture_runs[key] = launch.call }
    end

    def setup
      reason = RealApp.unavailable_reason(page: self.class.page?)
      skip "real-window tests cannot run here: #{reason}" if reason
    end

    # Fails with the app's output unless it ended on its own, and on macOS
    # if it ever came to the front, taking the keyboard from whoever was
    # typing. Where Frontmost is not available that check passes silently
    # (see watch_front).
    def assert_finished(run)
      refute run.timed_out, "the app was killed, #{run.verdict}\n#{run.describe}"
      refute run.activated, "the app came to the front instead of running in the background\n#{run.describe}"
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
