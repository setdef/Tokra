# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"

# A Tokra::Window as a dialog's parent, as Tauri's set_parent takes its
# Window (lib.rs:287-302, 460-478; ADR 013). The window is a real
# Tokra::Window on a real app handle, and its native stand-in answers the
# tagged Arrays ext/tokra/src/raw_handle.rs builds. Each dialog is read
# back through rfd's own Debug text, so what reaches rfd is what is
# checked. The real windows are in test_dialog_window.rb.
class TestParent < Minitest::Test
  include DialogTest

  # The Debug text rfd prints for the parents these tests give it
  # (rfd 0.17.2's derived Debug of raw-window-handle 0.6.2's types).
  XLIB_PARENT = "parent: Some(Xlib(XlibWindowHandle { window: 60817415, visual_id: 0 })), " \
    "parent_display: Some(Xlib(XlibDisplayHandle { display: Some(0x9000), screen: 0 }))"
  WIN32_PARENT = "parent: Some(Win32(Win32WindowHandle { hwnd: 7, hinstance: Some(9) })), " \
    "parent_display: Some(Windows(WindowsDisplayHandle))"

  # What tao answers for a window on each platform, in the native layer's
  # tagged form.
  NATIVE = {
    linux: [[:Xlib, 0x3A00007, 0], [:Xlib, 0x9000, 0]],
    windows: [[:Win32, 7, 9], [:Windows]],
    macos: [[:AppKit, 0x6000_0000_1000], [:AppKit]],
  }.freeze

  def setup
    @app = build_app
    build_plugin(@app)
    @dialog = @app.handle.dialog
  end

  # A Tokra::Window registered on the app, whose native window answers
  # +window_handle+ and +display_handle+.
  private def window(window_handle, display_handle)
    @app.handle.windows.clear
    stub_webview(@app.handle, window_handle:, display_handle:).window
  end

  # This platform's window, as tao would answer for it.
  private def platform_window
    window(*NATIVE.fetch(PLATFORM))
  end

  def test_a_window_without_handles_is_no_parent
    parent = window([:Unavailable], [:Unavailable])

    assert_includes @dialog.file.set_parent(parent).to_async_file_dialog.inspect, "parent: None"
    assert_includes @dialog.message("m").parent(parent).to_async_message_dialog.inspect, "parent: None"
  end

  # Tauri replaces the parent only when both handles are Ok, so a failed
  # one leaves the earlier parent in place.
  def test_a_window_whose_handles_fail_keeps_the_earlier_parent
    builder = @dialog.file.set_parent(window([:Win32, 7, 9], [:Windows]))
    earlier = builder.instance_variable_get(:@parent)

    builder.set_parent(window([:Unavailable], [:Unavailable]))

    refute_nil earlier
    assert_same earlier, builder.instance_variable_get(:@parent)
  end

  def test_an_x11_window_parents_the_dialog_on_linux
    skip_unless_platform(:linux)

    assert_includes @dialog.file.set_parent(platform_window).to_async_file_dialog.inspect, XLIB_PARENT
    assert_includes @dialog.message("m").parent(platform_window).to_async_message_dialog.inspect, XLIB_PARENT
  end

  def test_a_win32_window_parents_the_dialog_on_windows
    skip_unless_platform(:windows)

    assert_includes @dialog.file.set_parent(platform_window).to_async_file_dialog.inspect, WIN32_PARENT
    assert_includes @dialog.message("m").parent(platform_window).to_async_message_dialog.inspect, WIN32_PARENT
  end

  # ferro-rfd binds no AppKit handle, since rfd follows it as a pointer,
  # so on macOS the window is no parent and ferro-rfd refuses nothing.
  def test_an_appkit_window_is_no_parent_on_macos
    skip_unless_platform(:macos)

    assert_includes @dialog.file.set_parent(platform_window).to_async_file_dialog.inspect, "parent: None"
    assert_includes @dialog.message("m").parent(platform_window).to_async_message_dialog.inspect, "parent: None"
  end

  # ferro-rfd binds no Wayland handle either.
  def test_a_wayland_window_is_no_parent
    wayland = window([:Wayland, 0x5000], [:Wayland, 0x7000])

    assert_nil @dialog.file.set_parent(wayland).instance_variable_get(:@parent)
    assert_nil @dialog.message("m").parent(wayland).instance_variable_get(:@parent)
  end

  # Each handle ferro-rfd cannot take is no parent on its own, whatever
  # the other handle is: a parent may be any object with the two methods.
  def test_each_handle_ferro_rfd_cannot_take_is_no_parent_whatever_its_pair
    parent = Data.define(:window_handle, :display_handle)
    handles = Tokra::RawWindowHandle
    win32 = handles::Win32WindowHandle.new(hwnd: 7, hinstance: 9)
    windows = handles::WindowsDisplayHandle.new
    [
      parent.new(handles::AppKitWindowHandle.new(ns_view: 0x6000), windows),
      parent.new(handles::WaylandWindowHandle.new(surface: 0x5000), windows),
      parent.new(win32, handles::AppKitDisplayHandle.new),
      parent.new(win32, handles::WaylandDisplayHandle.new(display: 0x7000)),
    ].each do |pair|
      assert_nil @dialog.file.set_parent(pair).instance_variable_get(:@parent), pair.inspect
    end
  end

  def test_a_tokra_handle_becomes_ferro_rfds_value
    kept = @dialog.file.set_parent(window([:Win32, 7, 9], [:Windows])).instance_variable_get(:@parent)
    assert_equal Ferro::Rfd::Win32WindowHandle.new(hwnd: 7, hinstance: 9), kept.window_handle
    assert_equal Ferro::Rfd::WindowsDisplayHandle.new, kept.display_handle

    kept = @dialog.message("m").parent(window([:Xlib, 42, 33], [:Xlib, nil, 1])).instance_variable_get(:@parent)
    assert_equal Ferro::Rfd::XlibWindowHandle.new(window: 42, visual_id: 33), kept.window_handle
    assert_equal Ferro::Rfd::XlibDisplayHandle.new(display: nil, screen: 1), kept.display_handle
  end
end
