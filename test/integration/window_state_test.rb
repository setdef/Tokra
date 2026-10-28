# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real window's getters and setters (plan 040), changed from another
# thread through Tokra::Window and read back from what tao reports. The
# fixture loads no page, so this runs on Windows as well as macOS and
# Linux, and it never brings the app to the front (assert_finished).
class WindowStateTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("window_state") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def macos?
    RbConfig::CONFIG["host_os"].include?("darwin")
  end

  def wayland?
    RbConfig::CONFIG["host_os"].include?("linux") && ENV["WAYLAND_DISPLAY"].to_s != "" &&
      ENV["GDK_BACKEND"] != "x11"
  end

  def test_the_scale_factor_is_the_monitors
    scale = @report["scale_factor"]

    assert_operator scale, :>, 0
    assert_in_delta scale, @report["current_monitor"]["scale_factor"]
    assert_in_delta scale, @report["main_thread_scale_factor"]
  end

  def test_the_monitors_describe_a_display_holding_the_window
    monitors = @report["available_monitors"]
    refute_empty monitors
    current = @report["current_monitor"]

    assert_includes monitors, current
    assert_includes monitors, @report["monitor_at_window"]
    %w[width height].each { |side| assert_operator current["size"][side], :>, 0 }
    work = current["work_area"]
    assert_operator work["size"]["width"], :<=, current["size"]["width"]
    assert_operator work["size"]["height"], :<=, current["size"]["height"]
    assert_operator work["size"]["height"], :>, 0
  end

  # On macOS the size is the webview's, as in Tauri (lib.rs:5195-5212):
  # the view tao measures stops following the window once wry replaces it.
  def test_a_logical_size_reaches_the_window_scaled
    assert_equal @report["logical_size_expected"], @report["logical_size"]
  end

  def test_a_physical_size_reaches_the_window_as_is
    assert_equal({ "width" => 500, "height" => 360 }, @report["physical_size"])
    assert_operator @report["outer_size"]["height"], :>=, 360
  end

  def test_a_logical_position_moves_the_window_scaled
    skip "Wayland gives no window position" if wayland?

    assert_equal @report["logical_position_expected"], @report["logical_position"]
    inner = @report["inner_position"]
    assert_operator inner["y"], :>=, @report["logical_position"]["y"]
  end

  # Tauri's macOS work area is the screen's visible frame, scaled
  # (tauri-runtime-wry src/monitor/macos.rs:8-34).
  def test_the_work_area_is_appkits_visible_frame
    skip "AppKit only" unless macos?

    visible = @report["appkit_visible_frame"]
    work = @report["current_monitor"]["work_area"]["size"]
    scale = @report["scale_factor"]
    assert_equal (visible["width"] * scale).round, work["width"], visible.inspect
    assert_equal (visible["height"] * scale).round, work["height"], visible.inspect
  end

  # AppKit's contentMinSize and contentMaxSize, in points.
  def test_size_limits_reach_appkit
    skip "AppKit only" unless macos?

    assert_in_delta 150.0, @report["appkit_limits"]["min_width"]
    assert_in_delta 900.0, @report["appkit_limits"]["max_width"]
  end

  # tao 0.34.5 has no maximize or minimize button setting on Linux and
  # always reports both enabled (src/window.rs:1009-1027,
  # platform_impl/linux/window.rs:614-616, 663-669).
  def test_each_flag_changes_reads_back_on_any_thread_and_restores
    linux = RbConfig::CONFIG["host_os"].include?("linux")
    unsupported = linux ? %w[maximizable minimizable] : []
    @report["flags"].each do |name, reads|
      if unsupported.include?(name)
        assert_equal({ "changed" => true, "on_main" => true, "restored" => true }, reads, name)
        next
      end
      # tao learns always-on-top from GDK's window-state-event, which only
      # a window manager sends (platform_impl/linux/window.rs:368-378);
      # CI's Xvfb has none.
      next if linux && name == "always_on_top"

      changed = name == "always_on_top"
      assert_equal changed, reads["changed"], "#{name}: #{reads.inspect}"
      assert_equal changed, reads["on_main"], "#{name}: #{reads.inspect}"
      assert_equal !changed, reads["restored"], "#{name}: #{reads.inspect}"
    end
  end

  def test_hide_and_show
    assert_equal({ "hidden" => false, "shown" => true }, @report["visible"])
  end

  def test_a_theme_set_is_the_theme_read
    assert_equal({ "dark" => { "name" => "Dark" }, "light" => { "name" => "Light" } }, @report["theme"])
  end

  # Tauri centers in the work area (window/mod.rs:58-67); AppKit centers
  # horizontally too and sits a little above the middle.
  def test_center_puts_the_window_in_the_middle_of_the_work_area
    skip "Wayland gives no window position" if wayland?

    centered = @report["centered"]
    work = centered["work_area"]
    left = centered["outer_position"]["x"] - work["position"]["x"]
    right = work["size"]["width"] - left - centered["outer_size"]["width"]
    assert_in_delta left, right, 2, centered.inspect
  end

  def test_maximize_and_unmaximize
    skip "maximizes only on Windows (see the fixture)" unless @report.key?("maximized")

    assert_equal({ "maximized" => true, "restored" => false }, @report["maximized"])
  end

  def test_a_new_window_is_neither_fullscreen_nor_minimized
    refute @report["fullscreen"]
    refute @report["minimized"]
  end

  # Tauri's WindowExt (tauri-runtime-wry src/window/): an attached sheet on
  # macOS, GTK's sensitivity on Linux, EnableWindow on Windows.
  def test_set_enabled_reads_back_through_is_enabled
    assert_equal({ "disabled" => false, "disabled_on_main" => false, "enabled" => true }, @report["enabled"])
  end

  # AppKit's contentMinSize and contentMaxSize, in points, from one
  # logical and one physical limit.
  def test_size_constraints_reach_appkit
    skip "AppKit only" unless macos?

    assert_in_delta 260.0, @report["constraint_limits"]["min_width"]
    assert_in_delta 880.0, @report["constraint_limits"]["max_width"]
  end

  def test_a_minimum_width_holds_a_smaller_size
    skip "Wayland gives no window size here" if wayland?

    assert_equal @report["constrained_min_width"], @report["constrained_width"]
  end

  def test_set_shadow_reaches_appkit
    skip "AppKit only" unless macos?

    assert_equal({ "without" => false, "with" => true }, @report["shadow"])
  end

  # tao's BadIcon text inside Tauri's InvalidIcon (tauri-runtime
  # lib.rs:137-139), raised before anything reaches the window.
  def test_an_icon_is_taken_and_a_bad_one_refused
    assert_nil @report["icon"]
    assert_equal "runtime error: invalid icon: The specified dimensions (2x2) don't match the number of pixels " \
      "supplied by the `rgba` argument (3). For those dimensions, the expected pixel count is 4.",
      @report["bad_icon"]
  end

  def test_background_colors_are_taken
    assert_equal "set", @report["background_color"]
  end

  # The event loop's window target, lent to the main thread while it runs,
  # answers as the window does.
  def test_the_app_handles_monitors_are_the_windows
    assert_equal({ "primary" => true, "available" => true, "at_window" => true, "on_main" => true },
      @report["handle_monitors"])
  end

  def test_the_cursor_position_is_a_physical_position
    expected = {
"handle" => "Tokra::PhysicalPosition",
"window" => "Tokra::PhysicalPosition",
"on_main" => "Tokra::PhysicalPosition",
}
    assert_equal expected, @report["cursor"]
  end
end
