# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# WebviewWindow sends each call to the half Tauri's sends it to, listens on
# the WebviewWindow target, and the manager finds one by label only when
# the window is a webview window (webview_window.rs:1382-2599; lib.rs:554-607;
# window/mod.rs:1082-1084).
class TestWebviewWindow < Minitest::Test
  def page = Tokra::WebviewUrl::App.new("index.html")

  # Runs an app and calls the block on the main thread once it is ready.
  def run_app(tasks: 0, &on_ready)
    StubNative.inject_event(Array.new(tasks) { Tokra::Native::TaskEvent.new })
    Tokra::Builder.default.run(native: StubNative) do |handle, event|
      on_ready&.call(handle) if event.is_a?(Tokra::RunEvent::Ready)
    end
  end

  # Registers a window "frame" holding a webview "inner", whose labels
  # differ, so it is no webview window, as phase 4's add_child makes one.
  def register_frame(handle)
    window = Tokra::Window.new(label: "frame", native: StubNative::Window.new(nil, "frame"), app_handle: handle)
    handle.windows["frame"] = window
    handle.webviews["inner"] = Tokra::Webview.new(label: "inner", native: StubNative::WebView.new([], label: "inner"),
      window:, app_handle: handle)
  end

  def test_window_calls_go_to_the_window_and_webview_calls_to_the_webview
    run_app do |handle|
      main = handle.get_webview_window("main")
      main.set_title("Both")
      main.set_always_on_top(true)
      main.eval("1 + 1")

      assert_equal "Both", main.title
      assert_equal "Both", main.window.native.title
      assert_equal ["1 + 1"], main.webview.native.evals.last(1)
      assert_equal "main", main.label
      assert_same main.webview.resources_table, main.resources_table, "Tauri's resources_table is the webview's"
      assert_same handle, main.app_handle
      assert_equal handle.cursor_position, main.cursor_position
      assert_equal Tokra::PhysicalSize.new(width: 1600, height: 1200), main.inner_size
    end
  end

  def test_set_background_color_colors_the_window_and_then_the_webview
    run_app do |handle|
      main = handle.get_webview_window("main")
      main.set_background_color(Tokra::Color.new(1, 2, 3, 255))

      assert_equal [[1, 2, 3, 255]], main.window.native.requests[:set_background_color]
      assert_equal [[1, 2, 3, 255]], main.webview.native.background_colors
    end
  end

  def test_on_window_event_hears_the_windows_events
    heard = []
    StubNative.inject_event(Tokra::Native::WindowMovedEvent.new("main", 4, 5))
    Tokra::Builder.default.run(native: StubNative) do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      handle.get_webview_window("main").on_window_event { |window_event| heard << window_event }
    end

    assert_equal [Tokra::WindowEvent::Moved.new(position: Tokra::PhysicalPosition.new(x: 4, y: 5))], heard
  end

  def test_listen_hears_events_sent_to_the_webview_window_target
    heard = []
    run_app do |handle|
      handle.get_webview_window("main").listen("ping") { |event| heard << event.payload }
      handle.emit_to(Tokra::EventTarget.webview_window("main"), "ping", "to the webview window")
      handle.emit_to(Tokra::EventTarget.window("main"), "ping", "to the window")
      handle.emit_to(Tokra::EventTarget.webview("main"), "ping", "to the webview")
      handle.emit_to("main", "ping", "to any of them")
    end

    assert_equal ['"to the webview window"', '"to any of them"'], heard
  end

  def test_once_hears_one_event_and_unlisten_removes_a_handler
    heard = []
    run_app do |handle|
      main = handle.get_webview_window("main")
      to_it = Tokra::EventTarget.webview_window("main")
      handle.emit_to(Tokra::EventTarget.webview("main"), "ping", 0)
      main.once("ping") { |event| heard << [:once, event.payload] }
      handle.emit_to(Tokra::EventTarget.webview("main"), "ping", 0)
      id = main.listen("ping") { |event| heard << [:listen, event.payload] }
      handle.emit_to(to_it, "ping", 1)
      main.unlisten(id)
      handle.emit_to(to_it, "ping", 2)
    end

    assert_equal [[:listen, "1"], [:once, "1"]], heard.sort
  end

  def test_two_webview_windows_with_one_webview_are_equal
    run_app do |handle|
      first = handle.get_webview_window("main")
      second = handle.get_webview_window("main")

      assert_equal first, second
      assert_equal first.hash, second.hash
      assert first.eql?(second)
      refute_equal first, handle.get_window("main")
    end
  end

  def test_the_manager_finds_only_webview_windows
    run_app do |handle|
      register_frame(handle)
      side = Tokra::WebviewWindowBuilder.new(handle, "side", page).build

      assert_equal side, handle.get_webview_window("side")
      assert_nil handle.get_webview_window("inner"), "a webview in a window of another label is no webview window"
      assert_nil handle.get_webview_window("ghost")
      assert_equal %w[main side], handle.webview_windows.keys
      assert_equal side, handle.get_window("main").get_webview_window("side"), "every handle finds it"
      assert handle.get_window("main").is_webview_window
      refute handle.get_window("frame").is_webview_window
    end
  end

  def test_get_focused_window_answers_the_focused_window
    run_app do |handle|
      side = Tokra::WebviewWindowBuilder.new(handle, "side", page).build
      assert_nil handle.get_focused_window

      side.window.native.state[:is_focused] = true
      assert_same side.window, handle.get_focused_window
    end
  end

  def test_a_window_that_cannot_answer_counts_as_not_focused
    run_app do |handle|
      side = Tokra::WebviewWindowBuilder.new(handle, "side", page).build
      side.window.native.state[:is_focused] = true
      side.window.native.close

      assert_nil handle.get_focused_window
    end
  end

  # A thread may build a window while the main thread walks the app's
  # windows: Ruby refuses a new key in a Hash it is iterating, so the
  # manager walks a snapshot (plan 052, Results 052b).
  def test_a_window_built_on_another_thread_while_the_main_thread_walks_the_windows
    built = nil
    run_app do |handle|
      handle.get_window("main").native.define_singleton_method(:is_focused) do
        built = Thread.new { Tokra::WebviewWindowBuilder.new(handle, "side", Tokra::WebviewUrl::App.new("x")).build }.value
        false
      end

      assert_nil handle.get_focused_window
    end

    assert_equal "side", built.label
  end

  def test_an_invoke_names_its_webview_window_or_nil
    run_app do |handle|
      register_frame(handle)
      main = Tokra::Ipc::Invoke.new(command: "c", payload: {}, responder: nil, webview: handle.get_webview("main"))
      inner = Tokra::Ipc::Invoke.new(command: "c", payload: {}, responder: nil, webview: handle.get_webview("inner"))

      assert_equal handle.get_webview_window("main"), main.webview_window
      assert_nil inner.webview_window
    end
  end

  def test_a_webview_answers_the_apps_cursor_position
    run_app do |handle|
      assert_equal Tokra::PhysicalPosition.new(x: 812.0, y: 455.5), handle.get_webview("main").cursor_position
    end
  end
end
