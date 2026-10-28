# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"
require "fileutils"
require "tmpdir"

# A real app restarts itself in a new process (Plan 039).
#
# Tauri's request_restart asks the loop to exit with RESTART_EXIT_CODE and,
# once RunEvent::Exit is out, process::restart spawns the current binary
# with the process's arguments and exits with 0 (app.rs:540-582,
# 1304-1311; process.rs:73-87). restart on the main thread skips the
# events. The fixture restarts through request_restart, restart from a
# thread, and restart on the main thread, then exits; it loads no page, so
# this runs on Windows too.
#
#   bundle exec ruby test/integration/fixtures/restart/app.rb --log=/tmp/restart.log
class RestartTest < RealApp::TestCase
  # Seconds the restarted processes get to finish after the first ends.
  PATIENCE = 60

  # An argument the fixture leaves in ARGV after OptionParser takes --log.
  ARGUMENT = "two words"

  def self.page?
    false
  end

  def setup
    super
    @first, @entries = self.class.fixture_run { launch }
    assert_finished @first
  end

  def launch(*)
    dir = Dir.mktmpdir("tokra-restart")
    log = File.join(dir, "restart.log")
    first = RealApp.launch("restart", "--log=#{log}", *, ARGUMENT)
    [first, wait_for_every_run(log, first)]
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  def test_each_restart_starts_one_process
    assert_equal [1, 2, 3], @entries.select { |entry| entry["event"] == "spawn" }.map { |entry| entry["run"] },
      describe
  end

  # A restart that ends the process inside a handler, after
  # request_restart, starts the only new process: Tauri's process::exit
  # ends it before the Exit arm could restart it again (process.rs:84).
  def test_a_restart_inside_a_handler_after_request_restart_starts_one_process
    first, entries = self.class.fixture_run(:restart_in_handler) { launch("--in-handler=restart") }
    assert_finished first
    detail = "#{first.describe}\n--- log\n#{entries.map(&:to_json).join("\n")}"
    assert_equal 0, first.status, detail
    assert_equal [1], entries.select { |entry| entry["event"] == "spawn" }.map { |entry| entry["run"] }, detail
    assert_equal %w[started ready exit-requested exit at_exit],
      entries.select { |entry| entry["run"] == 1 && entry["event"] != "spawn" }.map { |entry| entry["event"] }, detail
    assert_equal 2, entries.count { |entry| entry["event"] == "started" }, detail
  end

  # An exit inside a handler after request_restart ends the app without a
  # restart, as process::exit does in Tauri before the Exit arm runs.
  def test_an_exit_inside_a_handler_after_request_restart_does_not_restart
    first, entries = self.class.fixture_run(:exit_in_handler) { launch("--in-handler=exit") }
    assert_finished first
    detail = "#{first.describe}\n--- log\n#{entries.map(&:to_json).join("\n")}"
    assert_equal 3, first.status, detail
    assert_equal %w[started ready exit-requested exit at_exit], entries.map { |entry| entry["event"] }, detail
  end

  def test_the_first_process_ends_with_zero
    assert_equal 0, @first.status, "process::restart exits with 0\n#{describe}"
  end

  def test_the_app_ran_four_times_and_heard_each_way_of_restarting
    assert_equal [
      %w[started ready exit-requested exit spawn at_exit],
      %w[started ready exit-requested exit spawn at_exit],
      %w[started ready spawn exit at_exit],
      %w[started ready exit-requested exit at_exit],
    ], (1..4).map { |run| entries(run).map { |entry| entry["event"] } }, describe
    assert_equal [Tokra::RESTART_EXIT_CODE, Tokra::RESTART_EXIT_CODE, 0],
      @entries.select { |entry| entry["event"] == "exit-requested" }.map { |entry| entry["code"] }, describe
  end

  def test_every_run_exits_with_zero
    assert_equal [0, 0, 0, 0], (1..4).map { |run| entries(run).last&.fetch("status", nil) }, describe
  end

  def test_every_run_gets_the_same_interpreter_script_arguments_and_directory
    starts = @entries.select { |entry| entry["event"] == "started" }
    assert_equal 4, starts.size, describe
    first = starts.first
    assert_equal RbConfig.ruby, first["args_os"][0]
    assert_equal File.join(RealApp::FIXTURES, "restart", "app.rb"), first["args_os"][1]
    assert_equal ARGUMENT, first["args_os"].last
    starts.each do |start|
      assert_equal first["args_os"], start["args_os"], "the restart runs args_os.skip(1) again"
      assert_equal [ARGUMENT], start["argv"], "each run parses the original arguments"
      assert_equal Dir.pwd, start["cwd"], "Command inherits the working directory"
    end
    assert_equal 4, starts.map { |start| start["pid"] }.uniq.size, "each run is a new process"
  end

  def test_every_run_loads_the_same_gems
    @entries.select { |entry| entry["event"] == "started" }.each do |start|
      assert start["bundler"], "Bundler's RUBYOPT reaches the new process\n#{describe}"
      assert_equal ENV.fetch("BUNDLE_GEMFILE", nil), start["gemfile"]
    end
  end

  # Waits until every process the restarts started has run its at_exit,
  # and answers every log entry. On time out, kills whatever runs are left.
  private def wait_for_every_run(log, first)
    deadline = RealApp.now + PATIENCE
    entries = []
    loop do
      entries = File.exist?(log) ? File.readlines(log).map { |line| JSON.parse(line) } : []
      count = -> (event) { entries.count { |entry| entry["event"] == event } }
      break if count.("at_exit") == count.("spawn") + 1
      break if RealApp.now > deadline || first.timed_out

      sleep 0.1
    end
    entries
  ensure
    finished = entries.select { |entry| entry["event"] == "at_exit" }.map { |entry| entry["run"] }
    entries.each do |entry|
      RealApp.signal(entry["pid"], :KILL) if entry["event"] == "started" && !finished.include?(entry["run"])
    end
  end

  private def entries(run)
    @entries.select { |entry| entry["run"] == run }
  end

  private def describe
    "#{@first.describe}\n--- log\n#{@entries.map(&:to_json).join("\n")}"
  end
end
