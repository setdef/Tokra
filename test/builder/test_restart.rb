# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# How an app restarts (Plan 039), with Ruby's Process.spawn stubbed so no
# second process starts.
#
# Mirrors Tauri's AppHandle::restart and request_restart (app.rs:540-582)
# and the run callback's Exit arm (app.rs:1304-1311): request_restart asks
# the loop to exit with RESTART_EXIT_CODE, which no handler can prevent,
# and once RunEvent::Exit is out, process::restart spawns the current
# binary with the process's arguments and exits with 0 (process.rs:73-87).
# restart on the main thread skips the events and restarts at once.
class TestBuilderRestart < Minitest::Test
  # Plugin recording the run events it hears into +log+, and running
  # +reaction+ on each.
  class RecordingPlugin < Tokra::Plugin
    attr_accessor :reaction, :log

    def name = "recording"

    def on_event(app, event)
      @log << event
      @reaction&.call(app, event)
    end
  end

  def setup
    StubNative.clear_event
    @log = []
    @plugin = RecordingPlugin.new(nil)
    @plugin.log = @log
  end

  def teardown
    StubNative.clear_event
  end

  def test_request_restart_asks_to_exit_with_the_restart_code_and_restarts_after_exit
    app = build
    exit = spawning do
      assert_raises(SystemExit) do
        app.run do |handle, event|
          handle.request_restart if event.is_a?(Tokra::RunEvent::Ready)
          event.api.prevent_exit if event.is_a?(Tokra::RunEvent::ExitRequested)
        end
      end
    end

    assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit, :spawn],
      kinds, "the restart follows RunEvent::Exit, and prevent_exit cannot stop it"
    assert_equal Tokra::RESTART_EXIT_CODE, @log[1].code
    assert_equal 0, exit.status, "process::restart exits with 0"
  end

  def test_the_restart_runs_the_interpreter_with_the_script_and_its_arguments
    app = build
    spawning { assert_raises(SystemExit) { app.run { |handle, event| restart_on_ready(handle, event) } } }

    binary = Tokra::Process.current_binary(app.handle.env)
    assert_equal [[[binary, binary], __FILE__, "two words"]], spawned,
      "Command::new(current_binary).args(args_os.skip(1)), with no shell between"
  end

  def test_request_restart_returns_nil_and_the_code_after_it_runs
    app = build
    after = nil
    spawning do
      assert_raises(SystemExit) do
        app.run { |handle, event| after = handle.request_restart if event.is_a?(Tokra::RunEvent::Ready) }
      end
    end

    assert_nil after
  end

  def test_restart_on_the_main_thread_restarts_at_once_without_asking
    app = build
    reached = false
    exit = spawning do
      assert_raises(SystemExit) do
        app.run do |handle, event|
          next unless event.is_a?(Tokra::RunEvent::Ready)

          handle.restart
          reached = true
        end
      end
    end

    assert_equal [Tokra::RunEvent::Ready, :spawn], kinds, "no ExitRequested and no Exit (app.rs:547-550)"
    assert_equal 0, exit.status
    refute reached, "restart never returns"
    assert_empty StubNative.event_loop_calls.select { |call| call == [:run] }, "the loop never started"
  end

  def test_restart_from_another_thread_asks_to_exit_and_restarts_after_the_loop
    app = build
    reached = false
    thread = nil
    spawning do
      assert_raises(SystemExit) do
        app.run do |handle, event|
          next unless event.is_a?(Tokra::RunEvent::Ready)

          thread = Thread.new do
            handle.restart
            reached = true
          end
          Thread.pass until thread.status == "sleep" || !thread.alive?
        end
      end
    end

    assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit, :spawn], kinds
    assert_equal Tokra::RESTART_EXIT_CODE, @log[1].code
    assert_predicate thread, :alive?, "the calling thread waits for the loop to end the process"
    refute reached
  ensure
    thread&.kill&.join
  end

  def test_request_restart_before_run_waits_for_the_loop
    app = build
    app.handle.request_restart

    spawning { assert_raises(SystemExit) { app.run } }

    assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit, :spawn], kinds
  end

  def test_request_restart_after_the_loop_has_ended_restarts_at_once
    app = build
    app.run
    @log.clear

    exit = spawning { assert_raises(SystemExit) { app.handle.request_restart } }

    assert_equal [:spawn], kinds, "with the loop gone, request_restart restarts (app.rs:579-581)"
    assert_equal 0, exit.status
  end

  def test_a_failed_spawn_is_reported_and_the_app_still_exits_with_zero
    app = build
    failing = -> (*) { raise Errno::ENOENT, "ruby" }
    exit = nil
    _, stderr = capture_io do
      Process.stub(:spawn, failing) do
        exit = assert_raises(SystemExit) { app.run { |handle, event| restart_on_ready(handle, event) } }
      end
    end

    assert_equal "failed to restart app: No such file or directory - ruby\n", stderr
    assert_equal 0, exit.status
  end

  def test_exit_with_the_restart_code_does_not_restart
    app = build
    spawning do
      app.run { |handle, event| handle.exit(Tokra::RESTART_EXIT_CODE) if event.is_a?(Tokra::RunEvent::Ready) }
    end

    assert_empty spawned, "only restart and request_restart set restart_on_exit"
    assert_equal Tokra::RESTART_EXIT_CODE, StubNative.exit_code
  end

  def test_a_raising_exit_handler_does_not_cancel_the_restart
    app = build
    _, stderr = capture_io do
      spawning do
        assert_raises(SystemExit) do
          app.run do |handle, event|
            handle.request_restart if event.is_a?(Tokra::RunEvent::Ready)
            raise "boom" if event.is_a?(Tokra::RunEvent::Exit)
          end
        end
      end
    end

    assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::ExitRequested, Tokra::RunEvent::Exit, :spawn], kinds
    assert_match(/boom/, stderr)
  end

  def test_the_app_manages_the_env_it_restarts_with
    app = build

    assert_equal ENV_FOR_TESTS, app.handle.env, "App::build manages Env::default (app.rs:2248-2249)"
    assert_same app.handle.state(Tokra::Env), app.handle.env
  end

  # The command line the apps restart with. A test run's own $0 may be
  # "-e", which a restart refuses.
  ENV_FOR_TESTS = Tokra::Env.new(args_os: [RbConfig.ruby, __FILE__, "two words"].freeze)

  private def build
    app = Tokra::Env.stub(:default, ENV_FOR_TESTS) { Tokra::Builder.default.build(native: StubNative) }
    app.handle.plugin(@plugin)
    app
  end

  private def restart_on_ready(handle, event)
    handle.request_restart if event.is_a?(Tokra::RunEvent::Ready)
  end

  # Runs the block with Process.spawn recording its arguments in the log,
  # and answers what the block returned.
  private def spawning(&)
    @spawned = []
    Process.stub(:spawn, lambda { |*command|
      @spawned << command
      @log << :spawn
      4242
    }, &)
  end

  private def spawned
    @spawned || []
  end

  private def kinds
    @log.map { |entry| entry.is_a?(Symbol) ? entry : entry.class }
  end
end
