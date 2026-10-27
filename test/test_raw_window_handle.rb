# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# Tests for Tokra::RawWindowHandle and the window_handle and display_handle
# methods Tauri's HasWindowHandle and HasDisplayHandle impls become
# (ADR 013). The native window is StubNative's, answering the tagged Arrays
# ext/tokra/src/raw_handle.rs builds; the app, its handle, its window, and
# its RuntimeContext are real, and the test's thread plays the main thread.
# The real-window tests in test/integration/window_handle_test.rb check
# what tao answers.
class TestRawWindowHandle < Minitest::Test
  Handles = Tokra::RawWindowHandle

  # raw-window-handle 0.6.2's Display text for each HandleError
  # (src/lib.rs:378-388).
  # SPDX-SnippetBegin
  # SPDX-License-Identifier: Apache-2.0 OR MIT
  # SPDX-SnippetCopyrightText: 2019 Osspial
  # SPDX-SnippetComment: raw-window-handle 0.6.2's HandleError messages, verbatim
  NOT_SUPPORTED = "the underlying handle cannot be represented using the types in this crate"
  UNAVAILABLE = "the underlying handle is not available"
  # SPDX-SnippetEnd

  def setup
    @app = Tokra::Builder.default.build(native: StubNative)
    @handle = @app.handle
    @native = StubNative::Window.new(nil)
    @window = Tokra::Window.new(label: "main", native: @native, app_handle: @handle)
  end

  # Registers the window as App#run does, so the app has one.
  private def open_window
    @handle.windows["main"] = @window
  end

  # Runs +call+ on another thread, plays the main thread for the one task
  # it queues, and returns what the thread returned or raised.
  private def from_another_thread(&call)
    caller = Thread.new do
      call.call
    rescue => e
      e
    end
    Thread.pass until caller.status == "sleep" || !caller.alive?
    @handle.runtime_context.handle_task
    caller.join(5)&.value
  end

  def test_the_handles_are_data_with_raw_window_handles_fields
    assert_equal %i[hwnd hinstance], Handles::Win32WindowHandle.members
    assert_empty Handles::WindowsDisplayHandle.members
    assert_equal %i[ns_view], Handles::AppKitWindowHandle.members
    assert_empty Handles::AppKitDisplayHandle.members
    assert_equal %i[window visual_id], Handles::XlibWindowHandle.members
    assert_equal %i[display screen], Handles::XlibDisplayHandle.members
    assert_equal %i[surface], Handles::WaylandWindowHandle.members
    assert_equal %i[display], Handles::WaylandDisplayHandle.members
  end

  def test_each_native_window_handle_becomes_its_value
    assert_equal Handles::Win32WindowHandle.new(hwnd: 7, hinstance: 9), Handles.window_handle([:Win32, 7, 9])
    assert_equal Handles::Win32WindowHandle.new(hwnd: 7, hinstance: nil), Handles.window_handle([:Win32, 7, nil])
    assert_equal Handles::AppKitWindowHandle.new(ns_view: 0x6000), Handles.window_handle([:AppKit, 0x6000])
    assert_equal Handles::XlibWindowHandle.new(window: 0x3A00007, visual_id: 33),
      Handles.window_handle([:Xlib, 0x3A00007, 33])
    assert_equal Handles::WaylandWindowHandle.new(surface: 0x5000), Handles.window_handle([:Wayland, 0x5000])
  end

  def test_each_native_display_handle_becomes_its_value
    assert_equal Handles::WindowsDisplayHandle.new, Handles.display_handle([:Windows])
    assert_equal Handles::AppKitDisplayHandle.new, Handles.display_handle([:AppKit])
    assert_equal Handles::XlibDisplayHandle.new(display: 0x9000, screen: 1), Handles.display_handle([:Xlib, 0x9000, 1])
    assert_equal Handles::XlibDisplayHandle.new(display: nil, screen: 0), Handles.display_handle([:Xlib, nil, 0])
    assert_equal Handles::WaylandDisplayHandle.new(display: 0x7000), Handles.display_handle([:Wayland, 0x7000])
  end

  def test_a_native_error_raises_the_handle_error_it_names_with_the_crates_message
    %i[window_handle display_handle].each do |reader|
      unavailable = assert_raises(Handles::HandleError::Unavailable) { Handles.public_send(reader, [:Unavailable]) }
      assert_equal UNAVAILABLE, unavailable.message
      not_supported = assert_raises(Handles::HandleError::NotSupported) { Handles.public_send(reader, [:NotSupported]) }
      assert_equal NOT_SUPPORTED, not_supported.message
    end
  end

  def test_handle_errors_are_standard_errors_outside_tokras_own
    assert_operator Handles::HandleError, :<, StandardError
    refute_operator Handles::HandleError, :<, Tokra::Error
    assert_operator Handles::HandleError::Unavailable, :<, Handles::HandleError
    assert_operator Handles::HandleError::NotSupported, :<, Handles::HandleError
  end

  def test_window_handle_answers_the_native_windows_handle
    @native.raw_window_handle = [:Xlib, 0x3A00007, 33]

    assert_equal Handles::XlibWindowHandle.new(window: 0x3A00007, visual_id: 33), @window.window_handle
  end

  def test_window_handle_raises_what_the_native_window_names
    error = assert_raises(Handles::HandleError::Unavailable) { @window.window_handle }
    assert_equal UNAVAILABLE, error.message
  end

  def test_window_handle_from_another_thread_waits_for_the_main_thread
    @native.raw_window_handle = [:Win32, 0x40A2C, nil]
    ran_on = nil
    native = @native
    native.define_singleton_method(:raw_window_handle) do
      ran_on = Thread.current
      super()
    end

    assert_equal Handles::Win32WindowHandle.new(hwnd: 0x40A2C, hinstance: nil), from_another_thread { @window.window_handle }
    assert_equal Thread.current, ran_on
  end

  # Tauri's getter fails once the loop is gone, and its window_handle turns
  # that into HandleError::Unavailable (tauri-runtime-wry lib.rs:2012-2018).
  def test_window_handle_after_the_loop_ended_raises_unavailable
    @handle.runtime_context.close

    error = Thread.new do
      @window.window_handle
    rescue => e
      e
    end.value
    assert_instance_of Handles::HandleError::Unavailable, error
    assert_equal UNAVAILABLE, error.message
  end

  def test_window_handle_raises_unavailable_when_the_loop_ends_before_it_answers
    caller = Thread.new do
      @window.window_handle
    rescue => e
      e
    end
    Thread.pass until caller.status == "sleep" || !caller.alive?
    @handle.runtime_context.close

    assert_instance_of Handles::HandleError::Unavailable, caller.join(5)&.value
  end

  def test_display_handle_before_the_app_has_a_window_raises_unavailable
    error = assert_raises(Handles::HandleError::Unavailable) { @handle.display_handle }
    assert_equal UNAVAILABLE, error.message
  end

  def test_display_handle_answers_the_first_windows_display
    open_window
    @native.raw_display_handle = [:Xlib, 0x9000, 0]
    expected = Handles::XlibDisplayHandle.new(display: 0x9000, screen: 0)

    assert_equal expected, @handle.display_handle
    assert_equal expected, @app.display_handle
    assert_equal expected, @window.display_handle
  end

  def test_a_windows_display_handle_is_the_apps
    open_window
    @native.raw_display_handle = [:Windows]
    other = Tokra::Window.new(label: "other", native: StubNative::Window.new(nil), app_handle: @handle)

    assert_equal Handles::WindowsDisplayHandle.new, other.display_handle
  end

  def test_display_handle_from_another_thread_waits_for_the_main_thread
    open_window
    @native.raw_display_handle = [:AppKit]
    ran_on = nil
    @native.define_singleton_method(:raw_display_handle) do
      ran_on = Thread.current
      super()
    end

    assert_equal Handles::AppKitDisplayHandle.new, from_another_thread { @handle.display_handle }
    assert_equal Thread.current, ran_on
  end

  def test_display_handle_after_the_loop_ended_raises_unavailable
    open_window
    @native.raw_display_handle = [:AppKit]
    @handle.runtime_context.close

    error = Thread.new do
      @handle.display_handle
    rescue => e
      e
    end.value
    assert_instance_of Handles::HandleError::Unavailable, error
  end
end
