# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# The taskbar and the title bar (plan 045): Tauri's progress bar, badges,
# overlay icon, and title bar style, and Window#webviews, through a real
# AppHandle and the stub native window.
class TestWindowTaskbar < Minitest::Test
  MACOS = RbConfig::CONFIG["host_os"].include?("darwin")
  WINDOWS = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)

  def app
    @app ||= Tokra::Builder.default.build(native: StubNative)
  end

  def app_handle
    app.handle
  end

  def native
    @native ||= StubNative::Window.new(nil, "main")
  end

  def window
    @window ||= Tokra::Window.new(label: "win", native:, app_handle:)
  end

  def teardown
    StubNative.clear_event
  end

  # Tauri names the desktop file after the package (window/mod.rs:2132-2168);
  # Tokra's is the product name or the program's file name (plan 045,
  # decision 4).
  def desktop_filename
    "#{File.basename($PROGRAM_NAME, '.*')}.desktop"
  end

  def test_progress_bar_status_and_state_are_tauris
    assert_equal %w[Error Indeterminate None Normal Paused],
      Tokra::ProgressBarStatus.constants.map { |name| Tokra::ProgressBarStatus.const_get(name).name }.sort
    state = Tokra::ProgressBarState.new

    assert_nil state.status
    assert_nil state.progress
  end

  def test_a_progress_bar_state_takes_only_a_status_and_a_whole_progress
    assert_raises(TypeError) { Tokra::ProgressBarState.new(status: "Normal") }
    assert_raises(TypeError) { Tokra::ProgressBarState.new(progress: 4.5) }
    error = assert_raises(RangeError) { Tokra::ProgressBarState.new(progress: -1) }
    assert_equal "integer -1 out of range of u64", error.message
    assert_equal (2 ** 64) - 1, Tokra::ProgressBarState.new(progress: (2 ** 64) - 1).progress
  end

  # ProgressBarStateWrapper (tauri-runtime-wry lib.rs:770-782), with the
  # desktop file name Tauri adds.
  def test_set_progress_bar_sends_the_status_progress_and_desktop_file
    state = Tokra::ProgressBarState.new(status: Tokra::ProgressBarStatus::Paused, progress: 40)

    assert_nil window.set_progress_bar(state)
    assert_equal ["Paused", 40, desktop_filename], native.requests[:set_progress_bar]

    window.set_progress_bar(Tokra::ProgressBarState.new(progress: 120))
    assert_equal [nil, 120, desktop_filename], native.requests[:set_progress_bar]
    assert_raises(TypeError) { window.set_progress_bar(40) }
  end

  # The Builder has no product name setter yet, so the test sets the
  # window config the App reads it from.
  def test_the_desktop_file_is_named_after_the_product
    builder = Tokra::Builder.default
    builder.__send__(:window_config)[:product_name] = "Ledger"
    handle = builder.build(native: StubNative).handle
    window = Tokra::Window.new(label: "win", native:, app_handle: handle)

    window.set_badge_count(2)
    assert_equal [2, "Ledger.desktop"], native.requests[:set_badge_count]
  end

  def test_set_badge_count_sends_the_count_or_nil
    assert_nil window.set_badge_count(7)
    assert_equal [7, desktop_filename], native.requests[:set_badge_count]

    window.set_badge_count(nil)
    assert_equal [nil, desktop_filename], native.requests[:set_badge_count]
    assert_raises(TypeError) { window.set_badge_count("7") }
    error = assert_raises(RangeError) { window.set_badge_count(2 ** 63) }
    assert_equal "integer #{2 ** 63} out of range of i64", error.message
    window.set_badge_count(-(2 ** 63))
    assert_equal [-(2 ** 63), desktop_filename], native.requests[:set_badge_count]
  end

  def test_set_title_bar_style_sends_its_name
    assert_equal %w[Overlay Transparent Visible],
      Tokra::TitleBarStyle.constants.map { |name| Tokra::TitleBarStyle.const_get(name).name }.sort

    assert_nil window.set_title_bar_style(Tokra::TitleBarStyle::Overlay)
    assert_equal ["Overlay"], native.requests[:set_title_bar_style]
    assert_raises(TypeError) { window.set_title_bar_style("Overlay") }
  end

  # Tauri compiles set_badge_label only for macOS and set_overlay_icon
  # only for Windows (window/mod.rs:2113-2149).
  def test_the_platform_only_setters_exist_only_on_their_platform
    assert_equal MACOS, Tokra::Window.method_defined?(:set_badge_label)
    assert_equal WINDOWS, Tokra::Window.method_defined?(:set_overlay_icon)
  end

  def test_on_macos_set_badge_label_sends_the_label_or_nil
    skip "Tauri's set_badge_label is macOS only" unless MACOS

    assert_nil window.set_badge_label("New")
    assert_equal ["New"], native.requests[:set_badge_label]
    window.set_badge_label(nil)
    assert_equal [nil], native.requests[:set_badge_label]
    assert_raises(TypeError) { window.set_badge_label(3) }
  end

  def test_on_windows_set_overlay_icon_sends_an_icon_or_nil
    skip "Tauri's set_overlay_icon is Windows only" unless WINDOWS

    image = Tokra::Image.new(rgba: "\xFF\x00\x00\xFF".b * 4, width: 2, height: 2)
    assert_nil window.set_overlay_icon(image)
    icon, = native.requests[:set_overlay_icon]
    assert_kind_of Tokra::Native::Icon, icon
    window.set_overlay_icon(nil)
    assert_equal [nil], native.requests[:set_overlay_icon]
  end

  # TaoIcon::try_from on the calling thread (tauri-runtime-wry
  # lib.rs:2364-2371).
  def test_on_windows_a_bad_overlay_icon_raises_invalid_icon_and_sends_nothing
    skip "Tauri's set_overlay_icon is Windows only" unless WINDOWS

    image = Tokra::Image.new(rgba: "\x00".b * 12, width: 2, height: 2)
    error = assert_raises(Tokra::Error::Runtime) { window.set_overlay_icon(image) }
    assert_match(/\Aruntime error: invalid icon: /, error.message)
    refute native.requests.key?(:set_overlay_icon)
  end

  def test_a_closed_window_ignores_the_taskbar_and_title_bar
    native.close

    window.set_progress_bar(Tokra::ProgressBarState.new(progress: 1))
    window.set_badge_count(1)
    window.set_title_bar_style(Tokra::TitleBarStyle::Visible)
    window.set_badge_label("x") if MACOS
    window.set_overlay_icon(nil) if WINDOWS
    assert_empty native.requests
  end

  # Tauri's Window::webviews: the webviews whose window is this one, as a
  # list (window/mod.rs:1071-1081).
  def test_webviews_are_the_ones_in_this_window
    other = Tokra::Window.new(label: "other", native: StubNative::Window.new(nil, "other"), app_handle:)
    mine = Tokra::Webview.new(label: "mine", native: StubNative::WebView.new, window:, app_handle:)
    theirs = Tokra::Webview.new(label: "theirs", native: StubNative::WebView.new, window: other, app_handle:)
    app_handle.webviews["mine"] = mine
    app_handle.webviews["theirs"] = theirs

    assert_equal [mine], window.webviews
    assert_equal [theirs], other.webviews
  end
end
