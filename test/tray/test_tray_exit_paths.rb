# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Every path that ends the process without the loop's RunEvent::Exit
# takes the trays off and clears the app's table first, as Tauri calls
# cleanup_before_exit on each (app.rs:532-581; plan 043, decision 7;
# plan 049, decision 4). Ruby's Process.spawn is stubbed
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

  # A resource that is not a tray, which only clearing the table removes.
  def resource = @handle.resources_table.add(Tokra::Image.new(rgba: "\0" * 4, width: 1, height: 1))

  def test_exit_after_the_loop_ended_cleans_up_before_ruby_exits
    @app.run
    made = tray("late")
    rid = resource

    exit = assert_raises(SystemExit) { @handle.exit(3) }

    assert_equal 3, exit.status
    assert made.native.removed?
    refute @handle.resources_table.has?(rid)
  end

  def test_restart_on_the_main_thread_cleans_up_before_it_restarts
    made = tray("main")
    rid = resource

    spawning { assert_raises(SystemExit) { @handle.restart } }

    assert made.native.removed?
    refute @handle.resources_table.has?(rid)
  end

  # Off the main thread with the loop gone, nothing can reach the native
  # tray, which only the main thread may drop; the app forgets it, and the
  # restart still happens (app.rs:563-566).
  def test_restart_from_a_thread_after_the_loop_ended_forgets_the_trays_clears_the_table_and_restarts
    @app.run
    made = tray("late")
    rid = resource

    spawning do
      thread = Thread.new do
        Thread.current.report_on_exception = false
        @handle.restart
      end
      assert_raises(SystemExit) { thread.value }
    end

    refute made.native.removed?
    assert_nil @handle.tray_manager.tray_resource_by_id("late")
    refute @handle.resources_table.has?(rid)
  end

  def test_request_restart_after_the_loop_ended_cleans_up
    @app.run
    made = tray("late")
    rid = resource

    spawning { assert_raises(SystemExit) { @handle.request_restart } }

    assert made.native.removed?
    refute @handle.resources_table.has?(rid)
  end

  private def spawning(&)
    Process.stub(:spawn, -> (*) { 4242 }, &)
  end
end
