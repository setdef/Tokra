# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../support/real_app"
require_relative "../support/keyboard_notice"

# Real context menus (plan 042, phase 3): the platform holds the menu's
# items at the position asked, other Ruby threads run while it tracks,
# blocks sent to the main thread wait for it to close, and an item chosen
# through AppKit or GTK reaches the app's listener. The fixture loads no
# page, so it runs on Windows too. On macOS the menu shows on screen and
# tracks the keyboard and mouse until it closes, so KeyboardNotice asks
# the person at the Mac to step away first; the app itself never comes to
# the front.
class ContextMenuTest < RealApp::TestCase
  # The points by which AppKit may raise a menu's window above the
  # location asked.
  MENU_INSET = 8

  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run do
      KeyboardNotice.taking_the_keyboard { RealApp.launch("context_menu") }
    end
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
  # window's top-left corner (platform_impl/gtk/mod.rs:1385-1447,
  # platform_impl/macos/mod.rs:1105-1130).
  def test_popup_at_places_the_menu_at_the_position
    skip "Windows places the menu by its own rules; the offset is reported, not asserted" if windows?

    scale = @report["scale_factor"]
    x, y = @report.dig("menu", "offset")
    assert_equal (30 * scale).round, x, @report.inspect
    if macos?
      # AppKit draws the menu's window a few points above the location,
      # so the first item, not the window's rounded edge, starts there
      # (5 points on macOS 27).
      assert_includes (((40 - MENU_INSET) * scale).round)..((40 * scale).round), y, @report.inspect
    else
      assert_equal (40 * scale).round, y
    end
  end

  # The popup releases the GVL (plan 042, decision 15): another Ruby
  # thread ran while the menu tracked and closed it, and a third ticked
  # meanwhile. Order proves it, not rate: with the GVL held, the fallback
  # timer, not the thread, would close the menu.
  def test_other_ruby_threads_run_while_a_menu_tracks
    %w[menu submenu].each do |name|
      assert_equal "thread", @report.dig(name, "dismissed_by"), @report.inspect
      assert_operator @report.dig(name, "ticks_while_tracking"), :>=, 1, @report.inspect
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

  private def macos?
    RbConfig::CONFIG["host_os"].include?("darwin")
  end
end
