# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"
require_relative "../support/test_app"

# Every WindowEvent tao reports, in Tauri's order: the run callback, then
# the window's listeners, the manager's first, which emits the tauri://
# event and then calls Builder#on_window_event's blocks, then the ones
# Window#on_window_event added; CloseRequested runs the listeners first
# (tauri-runtime-wry lib.rs:4126-4148, 4262-4290; manager/window.rs:79-100,
# 159-277).
class TestBuilderWindowEvents < Minitest::Test
  T = Tokra::EventTarget

  # Records the run events it hears and, at Ready, listens in the page for
  # every tauri:// event with the window's target, and in Ruby.
  class RecordingPlugin < Tokra::Plugin
    def name = "recording"

    def on_event(app, event)
      log = Thread.current[:window_events_log]
      case event
      when Tokra::RunEvent::Ready
        window = app.get_window("main")
        webview = app.get_webview("main")
        Thread.current[:window_events_listen].each { |name, target| webview.listen_js(name, target, 1) }
        window.on_window_event { |heard| log << [:window_listener, heard.class] }
        window.listen_any("tauri://destroyed") { |heard| log << [:ruby_listener, heard.payload] }
      when Tokra::RunEvent::WindowEvent then log << [:run_event, event.event.class]
      end
    end
  end

  def setup
    StubNative.clear_event
    StubNative::WebView.instances.clear
    Thread.current[:window_events_log] = []
    Thread.current[:window_events_listen] = []
  end

  def teardown
    StubNative.clear_event
  end

  def test_resized_carries_the_windows_inner_size_and_runs_in_tauris_order
    listen_in_page("tauri://resize")
    run_with(Tokra::Native::WindowResizedEvent.new("main"))

    assert_equal [
      [:run_event, Tokra::WindowEvent::Resized],
      [:builder, Tokra::WindowEvent::Resized],
      [:window_listener, Tokra::WindowEvent::Resized],
    ], log.first(3)
    assert_equal Tokra::PhysicalSize.new(width: 1600, height: 1200), heard_by_builder.first.size
    assert_page_heard "tauri://resize", '{"width":1600,"height":1200}'
  end

  def test_moved_carries_the_position
    listen_in_page("tauri://move")
    run_with(Tokra::Native::WindowMovedEvent.new("main", -5, 40))

    assert_equal Tokra::PhysicalPosition.new(x: -5, y: 40), heard_by_builder.first.position
    assert_page_heard "tauri://move", '{"x":-5,"y":40}'
  end

  def test_focus_and_blur
    listen_in_page("tauri://focus")
    listen_in_page("tauri://blur")
    run_with(Tokra::Native::WindowFocusedEvent.new("main", true), Tokra::Native::WindowFocusedEvent.new("main", false))

    assert_equal [true, false], heard_by_builder.map(&:focused)
    emitted = page_emits
    assert_equal ["tauri://focus", "tauri://blur"], emitted.map(&:first)
    assert_equal %w[null null], emitted.map(&:last)
  end

  def test_scale_factor_changed_carries_both_fields
    listen_in_page("tauri://scale-change")
    run_with(Tokra::Native::WindowScaleFactorChangedEvent.new("main", 1.5, 1200, 900))

    event = heard_by_builder.first
    assert_in_delta 1.5, event.scale_factor
    assert_equal Tokra::PhysicalSize.new(width: 1200, height: 900), event.new_inner_size
    assert_page_heard "tauri://scale-change", '{"scaleFactor":1.5,"size":{"width":1200,"height":900}}'
  end

  def test_theme_changed_maps_tao_themes_as_tauri_does
    listen_in_page("tauri://theme-changed")
    run_with(Tokra::Native::WindowThemeChangedEvent.new("main", "dark"), Tokra::Native::WindowThemeChangedEvent.new("main", "other"))

    assert_equal [Tokra::Theme::Dark, Tokra::Theme::Light], heard_by_builder.map(&:theme)
    assert_equal ['"dark"', '"light"'], page_emits.map(&:last)
  end

  # A webview window's drops reach every target with its label
  # (manager/window.rs:194-266), and paths are Pathnames
  # (tauri-runtime-wry lib.rs:4669-4698).
  def test_drag_and_drop_are_window_events_sent_to_the_label
    %w[tauri://drag-enter tauri://drag-over tauri://drag-drop tauri://drag-leave].each do |name|
      listen_in_page(name, T.webview("main"))
    end
    run_with(
      Tokra::Native::DragDropEvent.new("main", "enter", ["/tmp/a.txt"], 100, 200),
      Tokra::Native::DragDropEvent.new("main", "over", [], 101, 201),
      Tokra::Native::DragDropEvent.new("main", "drop", ["/tmp/a.txt", "/tmp/b"], 102, 202),
      Tokra::Native::DragDropEvent.new("main", "leave", [], 0, 0)
    )

    events = heard_by_builder.map(&:event)
    assert_equal [Tokra::DragDropEvent::Enter, Tokra::DragDropEvent::Over, Tokra::DragDropEvent::Drop, Tokra::DragDropEvent::Leave],
      events.map(&:class)
    assert_equal [Pathname("/tmp/a.txt"), Pathname("/tmp/b")], events[2].paths
    assert_equal Tokra::PhysicalPosition.new(x: 100.0, y: 200.0), events[0].position
    assert_equal [
      ["tauri://drag-enter", '{"paths":["/tmp/a.txt"],"position":{"x":100.0,"y":200.0}}'],
      ["tauri://drag-over", '{"position":{"x":101.0,"y":201.0}}'],
      ["tauri://drag-drop", '{"paths":["/tmp/a.txt","/tmp/b"],"position":{"x":102.0,"y":202.0}}'],
      ["tauri://drag-leave", "null"],
    ], page_emits
  end

  # emit_to_window reaches Window and WebviewWindow targets with the
  # window's label, and no other (manager/window.rs:125-138).
  def test_window_events_reach_only_the_windows_window_and_webview_window_targets
    [T.labeled("main"), T.webview_window("main"), T.webview("main"), T.window("main"), T.window("other")]
      .each { |target| listen_in_page("tauri://resize", target) }
    run_with(Tokra::Native::WindowResizedEvent.new("main"))

    ids = StubNative::WebView.instances.first.evals.filter_map { |script| script[%r{'tauri://resize'.*\}, (\[[\d,]*\])}, 1] }
    assert_equal ["[1,3]"], ids, "the WebviewWindow and Window listeners, by the ids they were given in order"
  end

  # A window whose native window has closed has no inner size, and its
  # Resized is dropped (tauri-runtime-wry lib.rs:557-575).
  def test_a_resize_after_the_native_window_closed_is_dropped
    run_with(Tokra::Native::WindowCloseEvent.new("main"), Tokra::Native::WindowResizedEvent.new("main"))

    refute_includes log.map(&:last), Tokra::WindowEvent::Resized
    assert_includes log.map(&:last), Tokra::WindowEvent::Destroyed, "the run went on to the window's end"
  end

  # The webview takes the theme after every listener heard it, and only
  # its own failure is logged (tauri-runtime-wry lib.rs:4126-4166).
  def test_on_windows_the_webview_takes_the_theme_after_the_listeners
    run_with(Tokra::Native::WindowThemeChangedEvent.new("main", "dark"), native: ThemedNative)

    assert_equal [
      [:run_event, Tokra::WindowEvent::ThemeChanged],
      [:builder, Tokra::WindowEvent::ThemeChanged],
      [:window_listener, Tokra::WindowEvent::ThemeChanged],
      [:set_theme, "Dark"],
    ], log
  end

  def test_a_failed_set_theme_is_logged
    Thread.current[:set_theme_error] = "refused"
    _, err = capture_io { run_with(Tokra::Native::WindowThemeChangedEvent.new("main", "light"), native: ThemedNative) }

    assert_includes err, "failed to set theme: refused"
  ensure
    Thread.current[:set_theme_error] = nil
  end

  def test_a_listener_that_raises_on_a_theme_change_is_not_taken_for_set_themes_failure
    Thread.current[:window_events_raise] = Tokra::WindowEvent::ThemeChanged
    error = assert_raises(RuntimeError) { run_with(Tokra::Native::WindowThemeChangedEvent.new("main", "dark"), native: ThemedNative) }

    assert_equal "listener failed", error.message
    refute_includes log, [:set_theme, "Dark"]
  ensure
    Thread.current[:window_events_raise] = nil
  end

  # StubNative whose webview takes a theme, as Native::WebView does on
  # Windows.
  module ThemedNative
    StubNative.constants.each { |name| const_set(name, StubNative.const_get(name)) unless name == :WebView }

    class WebView < StubNative::WebView
      def set_theme(name)
        raise Thread.current[:set_theme_error] if Thread.current[:set_theme_error]

        Thread.current[:window_events_log] << [:set_theme, name]
        nil
      end
    end
  end

  def test_on_webview_event_does_not_hear_a_webview_windows_drops
    heard = Thread.current[:webview_events] = []
    StubNative.inject_event(Tokra::Native::DragDropEvent.new("main", "leave", [], 0, 0))
    run_test_app(
      Tokra::Builder.default
        .on_webview_event(&Ractor.shareable_proc { |_webview, event| Thread.current[:webview_events] << event })
    )

    assert_empty heard
  end

  # The close request runs the listeners, then the run callback; a page
  # listening for tauri://close-requested on this window prevents the
  # close (manager/window.rs:166-171).
  def test_close_requested_listens_first_and_a_page_listener_prevents_the_close
    listen_in_page("tauri://close-requested")
    run_with(Tokra::Native::WindowCloseEvent.new("main"))

    assert_equal [
      [:builder, Tokra::WindowEvent::CloseRequested],
      [:window_listener, Tokra::WindowEvent::CloseRequested],
      [:run_event, Tokra::WindowEvent::CloseRequested],
    ], log
    assert_predicate heard_by_builder.first.api, :prevented?
    refute_predicate StubNative.windows.first, :closed?
    assert_page_heard "tauri://close-requested", "null"
  end

  def test_a_page_listening_elsewhere_does_not_prevent_the_close
    listen_in_page("tauri://close-requested", T.window("other"))
    run_with(Tokra::Native::WindowCloseEvent.new("main"))

    assert_predicate StubNative.windows.first, :closed?
  end

  # Destroyed reaches Ruby listeners of the window; the window and its
  # webview have left the manager first, so the page hears nothing
  # (app.rs:2391-2398, manager/mod.rs:651-658).
  def test_destroyed_reaches_ruby_after_the_run_callback
    listen_in_page("tauri://destroyed")
    run_with(Tokra::Native::WindowCloseEvent.new("main"))

    assert_equal [
      [:run_event, Tokra::WindowEvent::Destroyed],
      [:ruby_listener, "null"],
      [:builder, Tokra::WindowEvent::Destroyed],
      [:window_listener, Tokra::WindowEvent::Destroyed],
    ], log.drop_while { |(_, kind)| kind != Tokra::WindowEvent::Destroyed }
    assert_empty page_emits.select { |(name, _)| name == "tauri://destroyed" }
  end

  def test_builder_listeners_receive_the_window_wrapper
    run_with(Tokra::Native::WindowFocusedEvent.new("main", true))

    assert_instance_of Tokra::Window, Thread.current[:window_events_windows].first
  end

  private def listen_in_page(name, target = T.window("main"))
    Thread.current[:window_events_listen] << [name, target]
  end

  private def run_with(*events, native: StubNative)
    StubNative.inject_event(events)
    Thread.current[:window_events_windows] = []
    app = build_test_app(
      Tokra::Builder.default
        .on_window_event(&Ractor.shareable_proc { |window, event|
          Thread.current[:window_events_windows] << window
          Thread.current[:window_events_log] << [:builder, event.class]
          (Thread.current[:window_events_builder] ||= []) << event
          raise "listener failed" if event.is_a?(Thread.current[:window_events_raise] || NilClass)
        }),
      native:
    )
    Thread.current[:window_events_builder] = []
    app.handle.plugin(RecordingPlugin.new(app.handle))
    app.run
  rescue SystemExit
    nil
  end

  private def log
    Thread.current[:window_events_log]
  end

  private def heard_by_builder
    Thread.current[:window_events_builder]
  end

  # The [event, payload] of each emit script the page evaluated for at
  # least one of its listeners.
  private def page_emits
    StubNative::WebView.instances.first.evals.filter_map do |script|
      script.match(/fn\(\{event: '([^']+)', payload: (.*)\}, \[\d[\d,]*\]\) \}\)\(\)\z/)&.captures
    end
  end

  private def assert_page_heard(name, payload)
    assert_includes page_emits, [name, payload]
  end
end
