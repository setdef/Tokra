# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../support/real_app"
require_relative "../support/keyboard_notice"

# A real tray menu (plan 043), opened the way tray-icon opens it for a
# click: -[NSStatusBarButton performClick:] on macOS and the
# WM_RBUTTONDOWN Shell_NotifyIcon posts on Windows. The fixture reads the
# menu while it tracks, lets another Ruby thread close it by choosing an
# item, and reports what the app's and the tray's listeners heard. On
# macOS the menu shows and tracks the keyboard and mouse until it closes,
# so KeyboardNotice asks the person at the Mac to step away first. Linux's
# tray menu belongs to the desktop's StatusNotifierItem host, which the
# tests do not run.
class TrayMenuTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    skip "Linux's tray menu is shown by the desktop's StatusNotifierItem host" if linux?
    @run = self.class.fixture_run do
      KeyboardNotice.taking_the_keyboard { RealApp.launch("tray_menu") }
    end
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def linux? = RbConfig::CONFIG["host_os"].include?("linux")

  def test_the_trays_menu_opens_with_its_items
    assert @report["opened"], @report.inspect
    assert_equal %w[Show Hide], @report["labels"]
  end

  # The menu tracks in a nested loop inside the platform's click handling;
  # tao's handler is not running then, so it keeps handing the GVL to
  # other Ruby threads (ADR 012): one of them closed the menu while it
  # tracked, and another ticked meanwhile. Order proves it, not rate.
  def test_other_ruby_threads_run_while_the_tray_menu_tracks
    assert_equal "thread", @report["dismissed_by"], @report.inspect
    assert_operator @report["ticks_while_tracking"], :>=, 1, @report.inspect
  end

  # A chosen item is a menu event: the app's listeners, then the tray
  # builder's on_menu_event, which joins them (tray/mod.rs:427-435,
  # app.rs:2436-2444). tao's loop runs while the menu unwinds, so they may
  # hear it before the click handling returns, as in Tauri.
  def test_the_chosen_item_reaches_the_app_and_the_trays_menu_listener
    log = @report["log"]
    assert_includes log, "menu returned"
    assert_equal ["app:tray-show", "tray:tray-show"], log.grep(/\A(app|tray):/)
  end

  # tray-icon sends a click before it opens the menu on Windows, where
  # the message is the click (platform_impl/windows/mod.rs:311-395); on
  # macOS it sends one from its view's mouseDown:, and performClick:
  # alone sends none (platform_impl/macos/mod.rs:313-326, 467-488).
  def test_the_click_event_tray_icon_sends_for_the_click
    events = @report["log"].select { |entry| entry.start_with?("event:") }
    expected = RbConfig::CONFIG["host_os"].include?("darwin") ? [] : ["event:Click:Right:Down"]
    assert_equal expected, events
  end
end
