# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Every path that ends the process without the loop's RunEvent::Exit
# takes the trays off first, as Tauri calls cleanup_before_exit on each
# (app.rs:532-581; plan 043, decision 7). Ruby's Process.spawn is stubbed
# so no second process starts.
class TestTrayExitPaths < Minitest::Test
  ENV_FOR_TESTS = Tokra::Env.new(args_os: [RbConfig.ruby, __FILE__].freeze)

  def setup
    @app = Tokra::Env.stub(:default, ENV_FOR_TESTS) { Tokra::Builder.default.build(native: StubNative) }
    @handle = @app.handle
  end

  def teardown
    StubNative.clear_event
  end

  def tray(id) = Tokra::Tray::TrayIconBuilder.with_id(id).build(@handle)

  def test_exit_after_the_loop_ended_takes_the_trays_off_before_ruby_exits
    @app.run
    made = tray("late")

    exit = assert_raises(SystemExit) { @handle.exit(3) }

    assert_equal 3, exit.status
    assert made.native.removed?
  end

  def test_restart_on_the_main_thread_takes_the_trays_off_before_it_restarts
    made = tray("main")

    spawning { assert_raises(SystemExit) { @handle.restart } }

    assert made.native.removed?
  end

  # Off the main thread with the loop gone, nothing can reach the native
  # tray, which only the main thread may drop; the app forgets it, and the
  # restart still happens (app.rs:563-566).
  def test_restart_from_a_thread_after_the_loop_ended_forgets_the_trays_and_restarts
    @app.run
    made = tray("late")

    spawning do
      thread = Thread.new do
        Thread.current.report_on_exception = false
        @handle.restart
      end
      assert_raises(SystemExit) { thread.value }
    end

    refute made.native.removed?
    assert_nil @handle.tray_manager.tray_resource_by_id("late")
  end

  def test_request_restart_after_the_loop_ended_takes_the_trays_off
    @app.run
    made = tray("late")

    spawning { assert_raises(SystemExit) { @handle.request_restart } }

    assert made.native.removed?
  end

  private def spawning(&)
    Process.stub(:spawn, -> (*) { 4242 }, &)
  end
end
