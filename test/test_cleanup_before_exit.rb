# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"
require_relative "support/test_app"

# App#cleanup_before_exit and AppHandle#cleanup_before_exit through a real
# App and AppHandle: Tauri's cleanup_before_exit (app.rs:1024-1038; plan
# 049, part A) takes the trays off, clears the app's, each window's, and
# each webview's resources tables, and on Windows hides each window.
class TestCleanupBeforeExit < Minitest::Test
  # A resource that records whether anything closed it.
  class Recorder
    include Tokra::Resource

    def closed? = @closed || false

    def close
      @closed = true
      nil
    end
  end

  def setup
    @app = build_test_app
    @handle = @app.handle
  end

  def teardown
    StubNative.clear_event
  end

  def test_the_apps_table_is_cleared_without_closing_its_resources
    resource = Recorder.new
    rid = @handle.resources_table.add(resource)

    assert_nil @handle.cleanup_before_exit

    refute @handle.resources_table.has?(rid)
    assert_raises(Tokra::Error::BadResourceId) { @handle.resources_table.get(rid) }
    refute resource.closed?, "ResourceTable::clear calls no close (resources/mod.rs:218-222)"
  end

  def test_the_loops_end_clears_the_main_windows_and_webviews_tables
    rids = {}
    @app.run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      rids[:window] = handle.get_window("main").resources_table.add(Recorder.new)
      rids[:webview] = handle.get_webview("main").resources_table.add(Recorder.new)
    end

    refute @handle.get_window("main").resources_table.has?(rids.fetch(:window))
    refute @handle.get_webview("main").resources_table.has?(rids.fetch(:webview))
  end

  def test_on_windows_the_trays_come_off_before_any_window_is_hidden
    run_app
    log = []
    tray = Tokra::Tray::TrayIconBuilder.with_id("late").build(@handle)
    logging(tray.native, :remove, :tray_removed, log)
    logging(main_window.native, :set_visible, :hidden, log)

    on(:windows) { @handle.cleanup_before_exit }

    assert_equal %i[tray_removed hidden], log
  end

  def test_only_windows_hides_each_window
    run_app

    %i[macos linux].each do |os|
      on(os) { @handle.cleanup_before_exit }

      assert main_window.native.is_visible, "#{os} keeps the window as it was (app.rs:1032-1033)"
    end
    on(:windows) { @handle.cleanup_before_exit }

    refute main_window.native.is_visible
  end

  # Off the main thread with the loop gone, the hide cannot reach the
  # window and raises Error::Runtime, which Tauri's let _ drops.
  def test_a_hide_that_fails_is_ignored_and_the_webviews_table_is_still_cleared
    run_app
    rid = @handle.get_webview("main").resources_table.add(Recorder.new)

    on(:windows) do
      thread = Thread.new do
        Thread.current.report_on_exception = false
        @handle.cleanup_before_exit
      end

      assert_nil thread.value
    end

    refute @handle.get_webview("main").resources_table.has?(rid)
    assert main_window.native.is_visible
  end

  def test_the_apps_cleanup_is_its_handles
    rid = @app.resources_table.add(Recorder.new)

    assert_nil @app.cleanup_before_exit

    refute @handle.resources_table.has?(rid)
  end

  # Tauri's callers all end the process, but Tokra's restart on the main
  # thread is followed by the loop's own cleanup (plan 049, decision 5).
  def test_a_second_cleanup_raises_nothing_and_changes_nothing
    run_app
    Tokra::Tray::TrayIconBuilder.with_id("late").build(@handle)
    rid = @handle.resources_table.add(Recorder.new)
    on(:windows) { @handle.cleanup_before_exit }

    assert_nil on(:windows) { @handle.cleanup_before_exit }

    refute @handle.resources_table.has?(rid)
    assert_nil @handle.tray_by_id("late")
    refute main_window.native.is_visible
  end

  private def main_window = @handle.get_window("main")

  # Runs the app to its end. On Windows the loop's own cleanup already hid
  # the window (app.rs:1032-1033), so it is shown again and every test
  # starts from a visible window whatever platform runs it.
  private def run_app
    @app.run
    main_window.native.set_visible(true)
  end

  # Runs the block as if on +os+, as Tauri's cfg(windows) sees it.
  private def on(os, &)
    Tokra::Menu.stub(:os, os, &)
  end

  # Appends +entry+ to +log+ each time +object+ is sent +name+.
  private def logging(object, name, entry, log)
    object.singleton_class.prepend(Module.new do
      define_method(name) do |*args|
        log << entry
        super(*args)
      end
    end)
  end
end
