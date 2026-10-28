# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Real context menus on Linux and Windows (plan 042, phase 3): the platform
# holds the menu's items at the position asked, other Ruby threads run
# while it tracks, blocks sent to the main thread wait for it to close, and
# an item chosen through GTK reaches the app's listener. The fixture loads
# no page, so it runs on Windows too.
class ContextMenuTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    # A macOS popup is modal and takes the keyboard of whoever is typing;
    # the stub and native tests cover macOS without showing one.
    skip "a macOS context menu is modal and takes the keyboard" if RbConfig::CONFIG["host_os"].include?("darwin")
    super
    @run = self.class.fixture_run { RealApp.launch("context_menu") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def test_the_platform_shows_each_menus_items
    assert_equal ["Copy Link", "Open"], @report.dig("menu", "labels")
    assert_equal ["Rename"], @report.dig("submenu", "labels")
    assert_nil @report["menu_answer"]
  end

  # muda places the menu's corner at the position, relative to the
  # window's top-left corner (platform_impl/gtk/mod.rs:1385-1447).
  def test_popup_at_places_the_menu_at_the_position
    skip "Windows places the menu by its own rules; the offset is reported, not asserted" if windows?

    scale = @report["scale_factor"]
    assert_equal [(30 * scale).round, (40 * scale).round], @report.dig("menu", "offset")
  end

  # The popup releases the GVL (plan 042, decision 15): another Ruby
  # thread kept ticking while the menu tracked, and closed it.
  def test_other_ruby_threads_run_while_a_menu_tracks
    %w[menu submenu].each do |name|
      assert_equal "thread", @report.dig(name, "dismissed_by"), @report.inspect
      assert_operator @report.dig(name, "ticks_while_tracking"), :>=, 10, @report.inspect
    end
  end

  # tao runs no handler while one runs (ADR 012), so the main thread's
  # queue waits for the menu to close, as Tauri's events do.
  def test_a_block_sent_to_the_main_thread_while_a_menu_tracks_runs_after_it_closes
    assert_equal ["submenu returned", "task sent while tracking"], @report["submenu_log"]
  end

  def test_an_item_chosen_in_the_menu_reaches_the_apps_listener
    skip "Windows' menu closes by cancelling, without a synthesized key" if windows?

    assert_includes @report["menu_log"], "heard ctx-copy"
    assert_includes @report["menu_log"], "task sent while tracking"
  end

  def test_on_windows_each_menu_has_its_popup_hmenu
    skip "HMENU is Windows'" unless windows?

    assert_equal [true, true], @report["hpopupmenu"]
  end

  private def windows?
    RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
  end
end
