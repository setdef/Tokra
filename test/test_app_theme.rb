# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "timeout"
require_relative "support/stub_native"

# App#set_theme and AppHandle#set_theme (plan 045, decision 7): Tauri
# themes each window's menu on Windows, then sets the theme on the event
# loop (app.rs:842-869; tauri-runtime-wry lib.rs:2697-2702, 3027-3029,
# 4006-4008).
class TestAppTheme < Minitest::Test
  def setup
    StubNative.clear_event
  end

  def teardown
    StubNative.clear_event
  end

  def app
    @app ||= Tokra::Builder.default.build(native: StubNative)
  end

  def handle
    app.handle
  end

  def run_app(app, &callback)
    app.run(&callback)
  rescue SystemExit
    nil
  end

  def test_with_a_loop_the_theme_reaches_it
    handle.runtime_context.window_target = StubNative::EventLoop.new

    assert_nil handle.set_theme(Tokra::Theme::Dark)
    assert_nil handle.set_theme(nil)
    assert_equal [[:set_theme, "Dark"], [:set_theme, nil]], StubNative.event_loop_calls
  end

  # Tauri's App sets it on the loop that exists from Builder::build;
  # Tokra's loop waits for App#run, which hands the theme over first.
  def test_a_theme_set_before_run_reaches_the_loop_before_it_runs
    assert_nil app.set_theme(Tokra::Theme::Light)
    assert_empty StubNative.event_loop_calls
    run_app(app)

    assert_equal [[:set_theme, "Light"], [:run]], StubNative.event_loop_calls
  end

  def test_nil_before_run_reaches_the_loop_as_the_systems_theme
    app.set_theme(nil)
    run_app(app)

    assert_equal [[:set_theme, nil], [:run]], StubNative.event_loop_calls
  end

  def test_without_a_theme_the_loop_keeps_the_systems
    run_app(app)

    assert_equal [[:run]], StubNative.event_loop_calls
  end

  # The setup hook runs after the loop exists, so its theme comes after
  # one set before App#run, and wins.
  def test_the_setup_hooks_theme_comes_after_an_earlier_one
    setup = Ractor.shareable_proc { |built| built.set_theme(Tokra::Theme::Dark) }
    app = Tokra::Builder.default.setup(&setup).build(native: StubNative)
    app.set_theme(Tokra::Theme::Light)
    run_app(app)

    assert_equal [[:set_theme, "Light"], [:set_theme, "Dark"], [:run]], StubNative.event_loop_calls
  end

  # App#run emits Ready on the main thread before the loop runs.
  def test_the_run_callback_themes_the_loop
    run_app(app) { |running, event| running.set_theme(Tokra::Theme::Dark) if event.is_a?(Tokra::RunEvent::Ready) }

    assert_equal [[:set_theme, "Dark"], [:run]], StubNative.event_loop_calls
  end

  def test_from_another_thread_the_main_thread_sets_it
    handle.runtime_context.window_target = StubNative::EventLoop.new
    handle.runtime_context.attach(StubNative::Proxy.new)
    Thread.new { handle.set_theme(Tokra::Theme::Dark) }.join
    assert_empty StubNative.event_loop_calls, "nothing runs off the main thread"

    Timeout.timeout(5) { handle.runtime_context.handle_task }
    assert_equal [[:set_theme, "Dark"]], StubNative.event_loop_calls
  end

  # Tauri drops the runtime's failure to send (lib.rs:2697-2702).
  def test_after_the_loop_has_ended_the_theme_is_dropped
    handle.runtime_context.window_target = StubNative::EventLoop.new
    handle.runtime_context.attach(StubNative::Proxy.new)
    handle.runtime_context.close

    assert_nil Thread.new { handle.set_theme(Tokra::Theme::Dark) }.value
    assert_empty StubNative.event_loop_calls
  end

  # A thread finds no loop, then App#run builds the loop and takes the
  # kept theme, still empty, before the thread keeps its theme. The
  # thread looks again after keeping it, finds the loop, and sends it
  # (plan 045, decision 7). The first look at the target plays App#run's
  # part at exactly that moment.
  def test_a_theme_kept_just_after_run_took_the_kept_one_still_reaches_the_loop
    context = handle.runtime_context
    target = StubNative::EventLoop.new
    app_handle = handle
    looks = 0
    context.define_singleton_method(:window_target) do
      looks += 1
      next target unless looks == 1

      app_handle.take_loop_theme
      nil
    end

    handle.set_theme(Tokra::Theme::Dark)
    assert_equal [[:set_theme, "Dark"]], StubNative.event_loop_calls
    assert_nil handle.take_loop_theme, "nothing is left for a later run"
  end

  # The other order: App#run takes the theme the thread kept, and the
  # thread, finding the theme gone, does not send it a second time.
  def test_a_theme_run_already_took_is_sent_once
    context = handle.runtime_context
    target = StubNative::EventLoop.new
    app_handle = handle
    looks = 0
    context.define_singleton_method(:window_target) do
      looks += 1
      next nil if looks == 1

      theme = app_handle.take_loop_theme
      target.set_theme(theme.first) if theme && looks == 2
      target
    end

    handle.set_theme(Tokra::Theme::Light)
    assert_equal [[:set_theme, "Light"]], StubNative.event_loop_calls
  end

  def test_only_a_theme_or_nil
    error = assert_raises(TypeError) { handle.set_theme("Dark") }
    assert_equal "wrong argument type String (expected Tokra::Theme)", error.message
  end

  # On Windows Tauri themes each window's menu with map_to_menu_theme,
  # Auto for None (app.rs:849-863).
  def test_on_windows_each_windows_menu_bar_follows
    app = Tokra::Builder.default.build(native: StubWindowsMenusNative)
    handle = app.handle
    with_menu = Tokra::Window.new(label: "a", native: StubWindowsMenusNative::Window.new(nil, "a"), app_handle: handle)
    without = Tokra::Window.new(label: "b", native: StubWindowsMenusNative::Window.new(nil, "b"), app_handle: handle)
    handle.windows["a"] = with_menu
    handle.windows["b"] = without
    with_menu.set_menu(Tokra::Menu::Menu.with_id(handle, "bar"))

    handle.set_theme(Tokra::Theme::Dark)
    handle.set_theme(nil)

    assert_equal [%w[bar Dark], ["bar", nil]], with_menu.native.menu_theme_calls
    assert_empty without.native.menu_theme_calls
    refute with_menu.native.requests.key?(:set_theme), "the windows keep their own themes"
  end
end
