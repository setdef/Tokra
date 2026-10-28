# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for run event fan-out to registered plugins.
#
# Mirrors Tauri's dispatch in on_event_loop_event (app.rs): every RunEvent
# reaches each plugin's on_event hook, before the user callback. Exit comes
# from the native loop's LoopDestroyedEvent, because tao's run never returns
# (tauri-runtime-wry lib.rs:4046-4047).
class TestBuilderPluginRunEvents < Minitest::Test
  # Plugin recording on_event calls.
  class RecordingPlugin < Tokra::Plugin
    attr_reader :events

    def initialize(app = nil, config = {})
      super
      @events = []
    end

    def name = "recording"

    def on_event(app, event)
      @events << [app, event]
    end
  end

  def test_plugins_receive_ready_and_exit_with_the_handle
    plugin = RecordingPlugin.new
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(plugin)

    app.run

    assert_equal [Tokra::RunEvent::Ready.new, Tokra::RunEvent::Exit.new],
      plugin.events.map(&:last), "plugin should receive Ready then Exit"
    assert(plugin.events.all? { |handle, _event| handle.equal?(app.handle) },
      "plugin should receive the app handle with each event")
  end

  def test_plugins_hear_each_event_before_the_user_callback
    order = []
    plugin = RecordingPlugin.new
    plugin.define_singleton_method(:on_event) { |_app, _event| order << :plugin }

    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(plugin)
    app.run { |_handle, _event| order << :callback }

    assert_equal [:plugin, :callback, :plugin, :callback], order,
      "each event should reach plugins before the user callback, like Tauri"
  end

  def test_plugins_receive_the_window_close_as_a_window_event
    plugin = RecordingPlugin.new
    app = Tokra::Builder.default.build(native: StubNative)
    app.handle.plugin(plugin)
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new)

    app.run

    events = plugin.events.map(&:last)
    close = events[1]
    assert_instance_of Tokra::WindowEvent::CloseRequested, close.event
    assert_equal [
      Tokra::RunEvent::Ready.new,
      Tokra::RunEvent::WindowEvent.new(label: "main", event: Tokra::WindowEvent::CloseRequested.new(api: close.event.api)),
      Tokra::RunEvent::WindowEvent.new(label: "main", event: Tokra::WindowEvent::Destroyed.new),
    ], events.first(3), "Ready, the close request, then the window's destruction"
    assert_equal Tokra::RunEvent::Exit.new, events.last, "Exit as the loop ends"
  ensure
    StubNative.clear_event
  end

  # A native loop that never reports its destruction: Exit must come from
  # LoopDestroyedEvent, not from App#run returning (tao's run never does).
  module SilentNative
    EventLoop = Class.new(StubNative::EventLoop) { def run(_callback) = nil }
    Window = StubNative::Window
    WebView = StubNative::WebView
    # The real menu classes, as every native stand-in carries them (plan 042).
    Menu = Tokra::Native::Menu
    Submenu = Tokra::Native::Submenu
    MenuItem = Tokra::Native::MenuItem
    CheckMenuItem = Tokra::Native::CheckMenuItem
    PredefinedMenuItem = Tokra::Native::PredefinedMenuItem
  end

  def test_exit_is_emitted_only_when_the_loop_is_destroyed
    plugin = RecordingPlugin.new
    app = Tokra::Builder.default.build(native: SilentNative)
    app.handle.plugin(plugin)

    app.run

    assert_equal [Tokra::RunEvent::Ready.new], plugin.events.map(&:last),
      "returning from the native run must not fabricate an Exit"
  ensure
    StubNative.clear_event
  end
end
