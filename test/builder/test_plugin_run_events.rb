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
# reaches each plugin's on_event hook, before the user callback.
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
end
