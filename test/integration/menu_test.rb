# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real app menu, read back from the platform and activated through the
# platform's own dispatch, so each event comes through muda's handler and
# tao's loop as a click's would (plan 042). The fixture loads no page, so
# this runs on Windows as well as macOS and Linux.
class MenuTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("menu") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def test_the_platform_holds_the_menu_the_builder_made
    assert_equal "fixture-bar", @report["menu_id"]
    assert_equal [["Fixture", [["Fixture Item", []], ["Fixture Check", []]]], ["Tools", [["Run Tool", []]]]],
      @report["tree"]
  end

  def test_a_thread_reads_an_item_through_the_main_thread
    assert_equal "Run Tool", @report["thread_text"]
  end

  # Tauri calls the app's listeners, then the window's, then plugins and
  # the run callback (app.rs:2436-2453, 2488-2494).
  def test_an_activated_item_reaches_the_app_then_the_window_then_the_run_callback
    assert @report["activated"], @report.inspect
    assert_equal %w[app:fixture-item window:main:fixture-item run:fixture-item], @report["heard"]
  end

  def test_an_activated_check_item_flips_its_check_mark_and_sends_its_event
    assert @report["activated_check"], @report.inspect
    assert_equal %w[app:fixture-check window:main:fixture-check run:fixture-check], @report["heard_check"]
    refute @report["checked_before"]
    assert @report["checked_after"]
  end

  # On macOS Tauri takes the menu off NSApp and leaves each window's
  # record of it (app.rs:925-962); elsewhere it takes it off the windows.
  def test_removing_the_apps_menu_takes_it_off_the_platform
    assert_equal "fixture-bar", @report["removed"]
    macos = RbConfig::CONFIG["host_os"].include?("darwin")
    assert_equal(macos ? "fixture-bar" : "", @report["window_menu"])
    assert_includes [nil, []], @report["tree_after_remove"]
  end
end
