# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real tray icon, read back from the platform and sent events through
# tray-icon's own dispatch, so each event comes through tray-icon's handler
# and tao's loop as the pointer's would (plan 043). The fixture loads no
# page and opens no menu.
class TrayTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("tray") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def os = Tokra::Menu.os

  def test_the_platform_shows_the_tray_the_builder_made
    case os
    when :macos
      assert_equal [{ "image" => true, "tooltip" => "Fixture Tip", "title" => "Fixture Title", "menu" => ["Open"] }], @report["built"]
    when :windows then assert_equal 1, @report["built"]
    else assert_equal ["tray-icon-0.png"], @report["built"].map { |name| name.sub(/-\d+-/, "-") }
    end
    assert @report["found"]
  end

  # Each setter reaches the platform's own tray: the button on macOS, the
  # icon file the AppIndicator reads on Linux.
  def test_the_platform_follows_each_setter
    case os
    when :macos
      assert_equal [{ "image" => false, "tooltip" => "Changed Tip", "title" => "Changed Title", "menu" => ["Open"] }], @report["changed"]
      assert_equal [{ "image" => true, "tooltip" => "Changed Tip", "title" => "Changed Title", "menu" => ["Open"] }], @report["icon_again"]
      assert_equal [{ "image" => false, "tooltip" => "Changed Tip", "title" => "Changed Title", "menu" => nil }],
        @report["menu_removed"], "set_menu(nil) takes the menu off the status item"
    when :windows then assert_equal 1, @report["changed"]
    else
      assert_empty @report["changed"], "set_icon(nil) removes the icon's file and writes none"
      assert_equal ["tray-icon-2.png"], @report["icon_again"].map { |name| name.sub(/-\d+-/, "-") }
    end
  end

  # macOS removes the status item to hide it and makes a new one to show
  # it (platform_impl/macos/mod.rs:192-204); Linux makes the indicator
  # Passive, which leaves its file.
  def test_hiding_and_showing_the_tray
    case os
    when :macos
      assert_empty @report["hidden"]
      assert_equal [{ "image" => true, "tooltip" => "Changed Tip", "title" => "Changed Title", "menu" => ["Open"] }], @report["shown"]
    when :windows then assert_equal [1, 1], @report.values_at("hidden", "shown")
    else assert_equal @report["icon_again"], @report["shown"]
    end
  end

  def test_the_rect_is_physical_where_tray_icon_has_one
    if os == :linux
      assert_nil @report["rect"]
    else
      kind, width, height = @report["rect"]
      assert_equal "Tokra::PhysicalPosition", kind
      assert_operator width, :>, 0
      assert_operator height, :>=, 0
    end
  end

  # Tauri calls the app's listeners, then the tray's (app.rs:2453-2472).
  def test_each_event_reaches_the_app_then_the_tray
    expected = {
      macos: %w[enter move leave],
      windows: %w[enter click_down click_up double_click],
      linux: [],
    }.fetch(os)
    assert_equal expected, @report["sent"]
    kinds = { macos: %w[Enter Move Leave], windows: %w[Enter Click Click DoubleClick], linux: [] }.fetch(os)
    assert_equal kinds.flat_map { |kind| ["app:#{kind}:fixture-tray", "tray:#{kind}:fixture-tray"] }, @report["heard"]
  end

  def test_removing_the_tray_takes_it_off_the_platform
    assert @report["removed"]
    assert_nil @report["found_after_remove"]
    case os
    when :macos then assert_empty @report["after_remove"]
    when :windows then assert_equal 0, @report["after_remove"]
    else assert_empty @report["after_remove"], "tray-icon removes its last file as the tray drops"
    end
  end
end
