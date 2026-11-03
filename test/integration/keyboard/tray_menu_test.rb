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

  # The stages the menu passes, in the order their causes force.
  CAUSAL_STAGES = %w[timers-set popup-called shown returned].freeze

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

  # A Win32 timer's block that raised is recorded, not lost (plan 051).
  def test_on_windows_no_timer_callback_raised
    skip "the fixture guards SetTimer callbacks only on Windows" unless windows?

    assert_equal [], @report["timer_errors"], @run.describe
  end

  # The fixture prints each stage it reaches (plan 051), so a hang names
  # its stage. These stages follow one another by cause, not by timing.
  def test_the_menu_reports_its_progress_in_order
    stages = @run.lines.grep(/\APROGRESS /).map { |line| line.split[1] }
    assert_equal %w[ready menus-built], stages.first(2), @run.describe
    mine = stages.filter_map { |stage| stage.delete_prefix("tray:") if stage.start_with?("tray:") }
    assert_equal CAUSAL_STAGES, mine.select { |stage| CAUSAL_STAGES.include?(stage) }, @run.describe
    assert_includes mine, "cancel-posted", @run.describe
  end

  # The menu's modal loop may stop delivering WM_TIMER on Windows (plan
  # 051), so the closer thread finds, reads, chooses from, and ends the
  # menu with no help from a main-thread timer: with the 50 ms timer
  # skipped, it still does, and the fallback never fires. It runs only in
  # Windows CI.
  def test_on_windows_the_closer_thread_alone_finds_and_ends_the_menu
    skip "the closer thread finds the menu window itself only on Windows" unless windows?

    run = self.class.fixture_run(:no_main_timer) do
      KeyboardNotice.taking_the_keyboard { RealApp.launch("tray_menu", "--no-main-timer") }
    end
    assert_finished run
    assert_equal 0, run.status, run.describe
    report = run.report
    refute_nil report, "the fixture printed no report\n#{run.describe}"
    stages = run.lines.grep(/\APROGRESS /).map { |line| line.split[1] }
    assert_equal %w[Show Hide], report["labels"], run.describe
    assert_equal [], report["timer_errors"], run.describe
    assert_equal "thread", report["dismissed_by"], run.describe
    assert_operator report["ticks_while_tracking"], :>=, 1, run.describe
    assert_includes stages, "tray:cancel-posted", run.describe
    refute_includes stages, "tray:main-timer-saw", run.describe
    assert_equal ["app:tray-show", "tray:tray-show"], report["log"].grep(/\A(app|tray):/), run.describe
  end

  # An exception the GVL hand-off inside the menu meets, here a
  # Thread#raise aimed at the main thread, ends the menu and the loop, and
  # EventLoop#run raises it (plan 053, decision 1): the main thread rescues
  # it, so it got there, and the fallback never had to close the menu
  # first. It runs only in Windows CI.
  def test_on_windows_an_exception_raised_while_the_menu_tracks_ends_it_and_the_loop
    skip "the closer thread finds the menu window itself only on Windows" unless windows?

    run = self.class.fixture_run(:raise_main) do
      KeyboardNotice.taking_the_keyboard { RealApp.launch("tray_menu", "--no-main-timer", "--raise-main") }
    end
    assert_finished run
    assert_equal 0, run.status, run.describe
    report = run.report
    refute_nil report, "the fixture printed no report\n#{run.describe}"
    stages = run.lines.grep(/\APROGRESS /).map { |line| line.split[1] }
    assert_includes stages, "tray:main-raised", run.describe
    assert_equal "raised while the menu tracks", report["raised"], run.describe
    refute report["fell_back"], run.describe
    refute_includes stages, "tray:fallback-fired", run.describe
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

  private def windows? = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
end
