# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real window's effects, taskbar, title bar, and the app's theme (plan
# 045), changed from another thread and read back from what each
# platform reports. The fixture loads no page, so this runs on Windows as
# well as macOS and Linux, and it never brings the app to the front
# (assert_finished).
class WindowEffectsTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("window_effects") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def macos?
    RbConfig::CONFIG["host_os"].include?("darwin")
  end

  def linux?
    RbConfig::CONFIG["host_os"].include?("linux")
  end

  def test_the_window_holds_its_webview
    assert_equal ["main"], @report["webviews"]
  end

  # macOS takes the first NSVisualEffectMaterial, Popover (6), with the
  # Active state (1), and keeps it for nil (vibrancy/macos.rs,
  # vibrancy/mod.rs:15-30; window-vibrancy src/macos/internal.rs).
  def test_on_macos_the_first_material_shows_behind_the_webview_and_stays
    skip "NSVisualEffectView is AppKit's" unless macos?

    expected = { "present" => true, "class" => "NSVisualEffectViewTagged", "material" => 6, "state" => 1 }
    assert_equal expected, @report["effect"]
    assert_equal expected, @report["effect_after_nil"]
  end

  # Windows takes Mica, the first of its effects, and clears it for nil
  # (vibrancy/windows.rs): DWMSBT_MAINWINDOW (2) then DWMSBT_DISABLE (1)
  # from build 22523, the Mica flag 1 then 0 from 22000.
  def test_on_windows_mica_is_the_backdrop_until_cleared
    backdrop = @report["backdrop"]
    skip "DWM backdrops are Windows'" unless backdrop
    skip "Windows build #{backdrop['build']} has no Mica" unless backdrop.key?("attribute")
    skip "DWM does not report attribute #{backdrop['attribute']}: #{backdrop['value']}" if backdrop["value"].is_a?(String)

    applied, cleared = (backdrop["attribute"] == 38) ? [2, 1] : [1, 0]
    assert_equal applied, backdrop["value"]
    assert_equal cleared, @report["backdrop_after_nil"]["value"]
  end

  # macOS shows the count as the Dock tile's label (tauri-runtime-wry
  # lib.rs:3482-3503; tao platform_impl/macos/badge.rs).
  def test_on_macos_the_badge_count_and_label_are_the_dock_tiles
    skip "the Dock tile is macOS'" unless macos?

    assert_equal "5", @report["badge_count"]
    assert_equal "New", @report["badge_label"]
    assert_nil @report["badge_cleared"]
  end

  # tao's Dock progress indicator (platform_impl/macos/progress_bar.rs).
  def test_on_macos_the_progress_bar_is_the_dock_tiles_and_none_hides_it
    skip "the Dock tile is macOS'" unless macos?

    assert_equal({ "badge" => nil, "progress" => 40.0, "progress_hidden" => false }, @report["progress"])
    assert_equal({ "badge" => nil, "progress" => 40.0, "progress_hidden" => true }, @report["progress_none"])
  end

  def test_on_windows_the_overlay_icon_is_taken
    skip "Tauri's set_overlay_icon is Windows only" unless @report.key?("overlay_icon")

    assert_equal "set", @report["overlay_icon"]
  end

  # Tauri's pairs of titlebarAppearsTransparent and the full-size content
  # view (lib.rs:3511-3534).
  def test_each_title_bar_style_reaches_appkit
    expected = if macos?
      {
        "Overlay" => { "transparent" => true, "full_size" => true },
        "Transparent" => { "transparent" => true, "full_size" => false },
        "Visible" => { "transparent" => false, "full_size" => true },
      }
    else
      { "Overlay" => "set", "Transparent" => "set", "Visible" => "set" }
    end
    assert_equal expected, @report["title_bar"]
  end

  # The event loop's theme (tauri-runtime-wry lib.rs:4006-4008), as each
  # platform keeps it.
  def test_the_apps_theme_reaches_the_platform
    expected = if macos?
      ["NSAppearanceNameDarkAqua", "NSAppearanceNameAqua", nil]
    elsif linux?
      [true, false, false]
    else
      ["Dark", "Light"]
    end
    assert_equal expected, @report["app_theme"].first(expected.size)
  end
end
