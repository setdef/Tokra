# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real window's raw handles, read the way a library on any thread reads
# them, and followed back to the window system (ADR 013). The fixture
# loads no page, so this runs on Windows as well as macOS and Linux.
class WindowHandleTest < RealApp::TestCase
  def self.page?
    false
  end

  # The window and display kinds tao 0.34.5 answers on each platform
  # (platform_impl/macos/window.rs:1494-1510, windows/window.rs:438-457,
  # linux/window.rs:948-999).
  def expected_kinds
    case RbConfig::CONFIG["host_os"]
    when /darwin/ then %w[AppKitWindowHandle AppKitDisplayHandle]
    when /mswin|mingw|cygwin/ then %w[Win32WindowHandle WindowsDisplayHandle]
    when /linux/
      wayland = ENV["WAYLAND_DISPLAY"].to_s != "" && ENV["GDK_BACKEND"] != "x11"
      wayland ? %w[WaylandWindowHandle WaylandDisplayHandle] : %w[XlibWindowHandle XlibDisplayHandle]
    end
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("window_handle") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def test_the_handles_are_this_platforms_kinds
    window_kind, display_kind = expected_kinds

    %w[main_window thread_window].each { |key| assert_equal window_kind, @report[key]["kind"], @report[key].inspect }
    %w[main_display thread_display app_display].each do |key|
      assert_equal display_kind, @report[key]["kind"], @report[key].inspect
    end
  end

  def test_every_window_handle_field_that_names_the_window_is_nonzero
    fields = @report["main_window"].except("kind", "hinstance", "visual_id")
    refute_empty fields
    fields.each { |name, value| assert_operator value, :>, 0, "#{name} is #{value.inspect}" }
    hinstance = @report["main_window"]["hinstance"]
    assert_operator hinstance, :>, 0 if @report["main_window"]["kind"] == "Win32WindowHandle"
  end

  # Window#window_handle from another thread asks the main thread, as
  # Tauri's dispatcher getter does, and gets the same answer.
  def test_a_thread_gets_the_same_handles_as_the_main_thread
    assert_equal @report["main_window"], @report["thread_window"]
    assert_equal @report["main_display"], @report["thread_display"]
  end

  # The handle names this window: the window system, asked through it,
  # reports the fixture's title.
  def test_the_window_handle_leads_to_this_window
    kind = @report["main_window"]["kind"]
    skip "nothing here follows a #{kind}" if kind == "WaylandWindowHandle"
    skip "no xdotool to name the X11 window" if kind == "XlibWindowHandle" && @report["native_title"].nil?

    assert_equal @report["title"], @report["native_title"]
  end

  # Window#set_always_on_top reaches the window system, as Tauri's does
  # through tao (tauri-runtime-wry lib.rs:3390; tao 0.34.5
  # platform_impl/macos/window.rs:1386-1393).
  def test_always_on_top_reaches_the_window_system
    skip "nothing here reads whether a #{@report['main_window']['kind']} is on top" if @report["native_on_top"].nil?

    assert @report["native_on_top"], @report.inspect
  end

  # Window#set_ignore_cursor_events reaches the window system, as Tauri's
  # does through tao (tauri-runtime-wry lib.rs:3461-3463; tao 0.34.5
  # platform_impl/macos/window.rs:969-975).
  def test_ignoring_cursor_events_reaches_the_window_system
    kind = @report["main_window"]["kind"]
    skip "nothing here reads whether a #{kind} lets the cursor through" if @report["native_ignores_cursor"].nil?

    assert @report["native_ignores_cursor"], @report.inspect
  end

  # On X11 every display handle is the first one tao opened, so each answer
  # names the same live connection, which Xlib reads its display name from
  # (ADR 013, decision 4).
  def test_an_x11_display_handle_is_one_live_connection
    skip "X11 only" unless @report["main_display"]["kind"] == "XlibDisplayHandle"

    displays = %w[main_display thread_display app_display].map { |key| @report[key]["display"] }
    assert_operator displays.first, :>, 0
    assert_equal [displays.first], displays.uniq
    assert_equal @report["display_env"], @report["xlib_display_name"]
  end

  # Tauri answers a closed window's handle with HandleError::Unavailable;
  # a Tokra window closes when its loop ends.
  def test_once_the_loop_has_ended_a_thread_gets_unavailable
    late = @run.lines.find { |line| line.start_with?("LATE ") }
    refute_nil late, @run.describe
    error = JSON.parse(late.delete_prefix("LATE "))
    assert_equal "Tokra::RawWindowHandle::HandleError::Unavailable", error["error"]
    assert_equal "the underlying handle is not available", error["message"]
  end
end
