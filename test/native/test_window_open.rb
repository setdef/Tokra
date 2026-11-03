# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Native::Window.empty and #open, and Native::WebView.empty and #open,
# against the real extension (plan 052, decision b3): an empty native
# answers as a closed one, #open fills it once with the title and size it
# is given, a native that was ever open never opens again, and #discard
# drops a window whose webview failed (decision b4).
#
# Then the builder's rows (plan 052, phase 3), through tao: each row a tao
# window can answer is read back from the window #open built, and the
# centering and overflow sums are read from where the window lands.
class TestNativeWindowOpen < Minitest::Test
  MACOS = RbConfig::CONFIG["host_os"].include?("darwin")
  LINUX = RbConfig::CONFIG["host_os"].include?("linux")

  # The webview attributes a page at Tokra's URL opens with.
  PAGE = { url: "tokra://localhost/", initialization_scripts: [] }.freeze

  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
    @proxy = @event_loop.create_proxy
  end

  def test_an_empty_window_answers_as_a_closed_one_until_open_fills_it
    window = Tokra::Native::Window.empty(@proxy)
    assert_nil window.title

    assert_nil window.open(@event_loop, "open-1", { title: "Opened", inner_size: [200.0, 150.0] })

    assert_equal "Opened", window.title
    width, height = window.inner_size(nil)
    scale = window.scale_factor
    assert_equal [200, 150], [(width / scale).round, (height / scale).round], "open builds the window at its size"
  ensure
    window&.close
  end

  def test_a_window_opens_once
    window = Tokra::Native::Window.empty(@proxy)
    window.open(@event_loop, "open-2", { title: "Once" })

    error = assert_raises(RuntimeError) { window.open(@event_loop, "open-2b", { title: "Twice" }) }
    assert_equal "Window is already open", error.message
  ensure
    window&.close
  end

  def test_a_closed_window_never_opens_again
    window = Tokra::Native::Window.empty(@proxy)
    window.open(@event_loop, "open-3", { title: "Closed" })
    window.close

    error = assert_raises(RuntimeError) { window.open(@event_loop, "open-3b", { title: "Again" }) }
    assert_equal "Window is already open", error.message
    assert_nil window.title
  end

  def test_discard_drops_the_window
    window = Tokra::Native::Window.empty(@proxy)
    window.open(@event_loop, "open-4", { title: "Discarded" })

    assert_nil window.discard
    assert_nil window.title
    assert_nil window.discard, "discarding twice does nothing"
  end

  def test_a_closed_webview_never_opens_again
    window = Tokra::Native::Window.new(@event_loop, "open-5")
    webview = Tokra::Native::WebView.empty(@proxy)
    webview.open(window, @proxy, "open-5", PAGE)
    webview.close

    error = assert_raises(RuntimeError) { webview.open(window, @proxy, "open-5", PAGE) }
    assert_equal "WebView is already open", error.message
  ensure
    window&.close
  end

  # Opens an empty window labeled +label+, hidden, with the rows the block
  # sets on a real WindowBuilder, so its Hash's keys are the ones the
  # native reads, and answers it.
  def open_window(label)
    builder = Tokra::WindowBuilder.new(nil, label).visible(false)
    yield builder
    window = Tokra::Native::Window.empty(@proxy)
    window.open(@event_loop, label, builder.native_attributes)
    window
  end

  def test_the_rows_tao_can_answer_read_back
    window = open_window("rows-1") do |builder|
      builder.decorations(false).resizable(false).always_on_top(true)
    end

    assert_equal [false, false, false, true],
      [window.is_decorated, window.is_resizable, window.is_visible, window.is_always_on_top]
  ensure
    window&.close
  end

  # Both themes, so one of them is not the system's.
  def test_a_window_opens_in_its_theme
    windows = [Tokra::Theme::Light, Tokra::Theme::Dark].map do |theme|
      open_window("theme-#{theme.name}") { |builder| builder.theme(theme) }
    end

    assert_equal %w[Light Dark], windows.map(&:theme)
  ensure
    windows&.each(&:close)
  end

  # A decorated window, so its buttons exist to turn off.
  def test_a_decorated_window_opens_without_its_close_button
    window = open_window("rows-2") { |builder| builder.closable(false) }

    refute window.is_closable
  ensure
    window&.close
  end

  def test_the_buttons_rows_read_back_where_tao_reads_them
    skip "tao's Linux window answers true for minimizable and maximizable" if LINUX
    window = open_window("rows-2b") { |builder| builder.minimizable(false).maximizable(false) }

    assert_equal [false, false], [window.is_minimizable, window.is_maximizable]
  ensure
    window&.close
  end

  # tao places a new window's frame there on Windows, and on macOS its
  # content, below the title bar (platform_impl/macos/window.rs:201-210).
  #
  # The windows are small, 200 by 150, so they fit any plausible screen
  # and the platform keeps them where they were asked to be. A macOS
  # runner moved a window of tao's default 800 by 600 physical, asked for
  # at (120, 140), to (120, 77), while in the same run a 500-by-360
  # physical window moved there by set_position stayed put; so the move
  # depended on the window's size (plan 052, "macOS CI fix (052c)"). As a
  # safeguard beyond that, the test reads the distance between two
  # windows, which an offset the platform applied equally to both would
  # not change. The distances across and down differ, so x and y crossed
  # over fail, and without the row both windows are centered and the
  # distance is zero.
  def test_a_window_opens_at_its_position
    skip "GTK reports a window's position once a window manager places it" if LINUX
    windows = []
    [[120, 140], [220, 290]].each do |x, y|
      windows << open_window("rows-3-#{x}") { |builder| builder.inner_size(200, 150).position(x, y) }
    end

    scale = windows.first.scale_factor
    points = windows.map do |window|
      (x, y), = MACOS ? window.inner_position : window.outer_position
      [(x / scale).round, (y / scale).round]
    end
    distance = [points[1][0] - points[0][0], points[1][1] - points[0][1]]
    assert_equal [100, 150], distance, -> { "read #{points.inspect} on #{@event_loop.primary_monitor.inspect}" }
  ensure
    windows&.each(&:close)
  end

  # The work area of the primary monitor, physical: [[x, y], [width, height]].
  def work_area = @event_loop.primary_monitor.first[3]

  def test_a_centered_window_is_centered_in_the_work_area_at_its_clamped_size
    skip "GTK reports a window's position once a window manager places it" if LINUX
    window = open_window("rows-4") { |builder| builder.inner_size(200, 150).min_inner_size(400, 300).center }

    scale = window.scale_factor
    (left, top), (width, height) = work_area
    (x, y), = window.outer_position
    clamped = [400 * scale, 300 * scale]
    # Tauri centers the clamped inner size, plus a Windows frame; the
    # 200-by-150 asked for would sit 100 by 75 points further right and
    # down.
    expected = [left + ((width - clamped[0]) / 2), top + ((height - clamped[1]) / 2)]
    assert_in_delta expected[0], x, 20 * scale, "centered across"
    assert_in_delta expected[1], y, 40 * scale, "centered down"
  ensure
    window&.close
  end

  def test_an_overflowing_window_is_trimmed_to_the_work_area
    window = open_window("rows-5") { |builder| builder.inner_size(20_000, 20_000).prevent_overflow }

    _, (width, height) = work_area
    inner_width, inner_height = window.inner_size(nil)
    assert_operator inner_width, :<=, width
    assert_operator inner_height, :<=, height
  ensure
    window&.close
  end

  # Tauri's runtime panics here, in dpi's f64::clamp, which would end the
  # process; Tokra refuses the window, and the next one opens.
  def test_a_minimum_larger_than_the_maximum_refuses_the_window_and_the_process_lives_on
    window = Tokra::Native::Window.empty(@proxy)
    attributes = Tokra::WindowBuilder.new(nil, "inverted").visible(false).min_inner_size(900, 700)
      .max_inner_size(300, 200).native_attributes

    error = assert_raises(RuntimeError) { window.open(@event_loop, "inverted", attributes) }
    assert_equal "the window's minimum inner size is larger than its maximum", error.message
    assert_nil window.title, "nothing was built"
    after = open_window("after-inverted") { |builder| builder.min_inner_size(300, 200).max_inner_size(900, 700) }
    refute_nil after.title, "the next window opens"
  ensure
    after&.close
  end

  # tao clamps a window's size by its limits only as it builds the window
  # (platform_impl/macos/window.rs:194-199, windows/window.rs:1209-1211);
  # its run-time setters hand the limits to AppKit, Win32's
  # WM_GETMINMAXINFO, and GTK's geometry hints without a clamp, as
  # Tauri's SetMinSize, SetMaxSize, and SetSizeConstraints arms pass them
  # (tauri-runtime-wry lib.rs:3398-3411). So inverted or NaN limits set at
  # run time reach no f64::clamp, and the window answers afterwards. A tao
  # that clamped there would panic here.
  def test_inverted_or_nan_limits_set_at_run_time_reach_no_clamp
    window = open_window("runtime-limits") { |builder| builder.inner_size(300, 200) }

    assert_nil window.set_inner_size_constraints([[false, 900.0], [false, 700.0], [false, 300.0], [false, 200.0]])
    assert_nil window.set_inner_size_constraints([[false, Float::NAN], nil, nil, nil])
    assert_nil window.set_max_inner_size([false, 300.0, 200.0])
    assert_nil window.set_min_inner_size([false, 900.0, 700.0])
    assert_nil window.set_inner_size([false, 500.0, 500.0])
    refute_nil window.inner_size(nil), "the window still answers"
  ensure
    window&.close
  end
end
