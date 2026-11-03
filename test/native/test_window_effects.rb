# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Plan 045's native setters against the real extension: a closed window
# ignores each, as plan 038 decided; a name the Ruby enums lack raises
# ArgumentError; each refuses another thread; and the event loop takes the
# app's theme before it runs. What each does to an open window is read
# back by the window_effects fixture.
class TestNativeWindowEffects < Minitest::Test
  SETTERS = {
    set_effects: [[%w[Mica Popover], "Active", 4.0, [1, 2, 3, 4]]],
    set_progress_bar: ["Normal", 50, "tokra.desktop"],
    set_badge_count: [3, "tokra.desktop"],
    set_title_bar_style: ["Overlay"],
  }.freeze

  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
    @window = Tokra::Native::Window.new(@event_loop, "window-effects-1")
  end

  def teardown
    @window&.close
  end

  def test_a_closed_window_ignores_each_new_setter
    @window.close

    SETTERS.each { |setter, args| assert_nil @window.public_send(setter, *args), setter }
    assert_nil @window.set_effects(nil)
    assert_nil @window.set_progress_bar(nil, nil, nil)
    assert_nil @window.set_badge_count(nil, nil)
    assert_nil @window.set_badge_label("1") if @window.respond_to?(:set_badge_label)
    assert_nil @window.set_overlay_icon(nil) if @window.respond_to?(:set_overlay_icon)
  end

  # Tauri compiles set_badge_label only for macOS and set_overlay_icon
  # only for Windows (window/mod.rs:2113-2149).
  def test_the_platform_only_setters_exist_only_on_their_platform
    host = RbConfig::CONFIG["host_os"]

    assert_equal host.include?("darwin"), @window.respond_to?(:set_badge_label)
    assert_equal host.match?(/mswin|mingw|cygwin/), @window.respond_to?(:set_overlay_icon)
  end

  def test_a_name_the_ruby_enums_lack_raises_argument_error
    @window.close
    {
      [:set_effects, [%w[Mica Frosted], nil, nil, nil]] => "unknown effect: Frosted",
      [:set_effects, [[], "Sometimes", nil, nil]] => "unknown effect state: Sometimes",
      [:set_progress_bar, "Done", nil, nil] => "unknown progress bar status: Done",
      [:set_title_bar_style, "Hidden"] => "unknown title bar style: Hidden",
    }.each do |(setter, *args), message|
      error = assert_raises(ArgumentError, setter) { @window.public_send(setter, *args) }
      assert_equal message, error.message
    end
  end

  def test_each_new_setter_off_the_windows_thread_raises_thread_error
    SETTERS.each do |setter, args|
      assert_raises(ThreadError, setter) do
        Thread.new do
          Thread.current.report_on_exception = false
          @window.public_send(setter, *args)
        end.value
      end
    end
  end

  # tao's EventLoopWindowTarget::set_theme, from the loop before it runs
  # (tauri-runtime-wry lib.rs:3027-3029). nil follows the system, so the
  # suite's appearance stays the system's.
  def test_the_loop_takes_the_systems_theme_and_refuses_an_unknown_one
    assert_nil @event_loop.set_theme(nil)

    error = assert_raises(ArgumentError) { @event_loop.set_theme("Sepia") }
    assert_equal "unknown theme: Sepia", error.message
    assert_raises(ThreadError) do
      Thread.new do
        Thread.current.report_on_exception = false
        @event_loop.set_theme(nil)
      end.value
    end
  end
end
