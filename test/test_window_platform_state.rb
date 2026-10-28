# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# The window state plan 040 deferred (plan 041): Tauri's own WindowExt
# code, size constraints, icons, background colors, and shadows, through a
# real AppHandle and the stub native window.
class TestWindowPlatformState < Minitest::Test
  def app_handle
    @app_handle ||= Tokra::Builder.default.build(native: StubNative).handle
  end

  def native
    @native ||= StubNative::Window.new(nil)
  end

  def window
    @window ||= Tokra::Window.new(label: "win", native:, app_handle:)
  end

  def test_set_enabled_changes_what_is_enabled_reads
    assert window.is_enabled

    assert_nil window.set_enabled(false)
    refute window.is_enabled
    window.set_enabled(true)
    assert window.is_enabled
  end

  def test_a_closed_window_cannot_say_whether_it_is_enabled
    native.close

    error = assert_raises(Tokra::Error::Runtime) { window.is_enabled }
    assert_equal "runtime error: failed to receive message from webview", error.message
  end

  # Each limit reaches tao as its own kind of unit, or none.
  def test_size_constraints_reach_tao_limit_by_limit
    constraints = Tokra::WindowSizeConstraints.new(
      min_width: Tokra::LogicalUnit.new(400),
      max_height: Tokra::PhysicalUnit.new(900)
    )

    assert_nil window.set_size_constraints(constraints)
    assert_equal [[[false, 400.0], nil, nil, [true, 900.0]]], native.requests[:set_inner_size_constraints]
  end

  def test_size_constraints_must_be_window_size_constraints
    assert_raises(TypeError) { window.set_size_constraints(Tokra::LogicalSize.new(width: 1, height: 1)) }
    refute native.requests.key?(:set_inner_size_constraints)
  end

  # Tauri converts the image to tao's icon before it sends anything
  # (tauri-runtime-wry lib.rs:2278-2286).
  def test_an_icon_is_built_from_the_image_and_sent
    image = Tokra::Image.new(rgba: "\xFF\x00\x00\xFF".b * 4, width: 2, height: 2)

    assert_nil window.set_icon(image)
    icon, = native.requests[:set_window_icon]
    assert_kind_of Tokra::Native::Icon, icon
  end

  # tao's BadIcon text inside Tauri's InvalidIcon (tauri-runtime
  # lib.rs:137-139), raised on the calling thread.
  def test_an_image_that_does_not_fill_its_size_raises_invalid_icon_and_sends_nothing
    image = Tokra::Image.new(rgba: "\x00".b * 12, width: 2, height: 2)

    error = assert_raises(Tokra::Error::Runtime) { window.set_icon(image) }
    assert_equal "runtime error: invalid icon: The specified dimensions (2x2) don't match the number of pixels " \
      "supplied by the `rgba` argument (3). For those dimensions, the expected pixel count is 4.",
      error.message
    refute native.requests.key?(:set_window_icon)
  end

  def test_an_icon_must_be_an_image
    assert_raises(TypeError) { window.set_icon("icon.png") }
  end

  def test_a_background_color_reaches_tao_as_rgba
    assert_nil window.set_background_color(Tokra::Color.new(1, 2, 3, 4))
    assert_equal [[1, 2, 3, 4]], native.requests[:set_background_color]

    window.set_background_color(nil)
    assert_equal [nil], native.requests[:set_background_color]
    assert_raises(TypeError) { window.set_background_color([1, 2, 3, 4]) }
  end

  def test_set_shadow_reaches_tao
    assert_nil window.set_shadow(false)
    assert_equal [false], native.requests[:set_shadow]
  end

  def test_a_closed_window_ignores_the_new_setters
    native.close

    window.set_enabled(false)
    window.set_shadow(false)
    window.set_background_color(nil)
    window.set_size_constraints(Tokra::WindowSizeConstraints.new)
    window.set_icon(Tokra::Image.new(rgba: "\x00".b * 4, width: 1, height: 1))
    assert_empty native.requests
  end

  # Tauri's Window::cursor_position asks its app handle (window/mod.rs:1643-1645).
  def test_cursor_position_is_the_app_handles
    app_handle.runtime_context.window_target = StubNative::EventLoop.new

    assert_equal Tokra::PhysicalPosition.new(x: 812.0, y: 455.5), window.cursor_position
  end

  def test_a_webview_background_color_reaches_wry_and_nil_asks_for_the_default
    native_webview = StubNative::WebView.new
    webview = Tokra::Webview.new(label: "win", native: native_webview, window:, app_handle:)

    assert_nil webview.set_background_color(Tokra::Color.new(30, 30, 30, 255))
    webview.set_background_color(nil)
    assert_equal [[30, 30, 30, 255], nil], native_webview.background_colors
    assert_raises(TypeError) { webview.set_background_color("#1e1e1e") }
  end

  # Tauri's runtime logs wry's failure (tauri-runtime-wry lib.rs:3745-3750).
  def test_a_webview_background_color_wry_refuses_is_logged
    native_webview = StubNative::WebView.new
    native_webview.background_color_error = RuntimeError.new("WebView2 refused")
    webview = Tokra::Webview.new(label: "win", native: native_webview, window:, app_handle:)

    _, err = capture_io { assert_nil webview.set_background_color(nil) }
    assert_equal "failed to set webview background color: WebView2 refused\n", err
  end
end
