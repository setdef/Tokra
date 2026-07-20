# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::PluginStore.
#
# The store routes plugin:NAME|command invokes to the registered plugin
# with that name, mirroring Tauri's PluginStore in plugin.rs.
class TestPluginStore < Minitest::Test
  # Minimal plugin recording extend_api and on_event calls.
  class RecordingPlugin < Tokra::Plugin
    attr_reader :invokes, :events

    def initialize(app = nil, config = {}, name: "recording", handles: true)
      super(app, config)
      @plugin_name = name
      @handles = handles
      @invokes = []
      @events = []
    end

    def name = @plugin_name

    def extend_api(invoke)
      @invokes << invoke
      @handles
    end

    def on_event(app, event)
      @events << [app, event]
    end
  end

  def test_register_returns_false_for_new_plugin
    store = Tokra::PluginStore.new
    refute store.register(RecordingPlugin.new),
      "register should return false when no plugin was replaced"
  end

  def test_register_returns_true_when_replacing_same_name
    store = Tokra::PluginStore.new
    store.register(RecordingPlugin.new)
    assert store.register(RecordingPlugin.new),
      "register should return true when replacing a same-named plugin"
  end

  def test_register_replaces_same_named_plugin
    store = Tokra::PluginStore.new
    original = RecordingPlugin.new
    replacement = RecordingPlugin.new
    store.register(original)
    store.register(replacement)

    store.extend_api("recording", build_invoke("cmd"))

    assert_empty original.invokes, "replaced plugin should not receive invokes"
    assert_equal 1, replacement.invokes.size, "replacement should receive the invoke"
  end

  def test_unregister_removes_plugin
    store = Tokra::PluginStore.new
    plugin = RecordingPlugin.new
    store.register(plugin)

    assert store.unregister("recording"), "unregister should return true when removed"

    store.extend_api("recording", build_invoke("cmd"))
    assert_empty plugin.invokes, "unregistered plugin should not receive invokes"
  end

  def test_unregister_returns_false_for_unknown_name
    store = Tokra::PluginStore.new
    refute store.unregister("missing"),
      "unregister should return false when no plugin had that name"
  end

  def test_extend_api_routes_to_named_plugin
    store = Tokra::PluginStore.new
    target = RecordingPlugin.new(name: "target")
    other = RecordingPlugin.new(name: "other")
    store.register(target)
    store.register(other)

    invoke = build_invoke("greet")
    handled = store.extend_api("target", invoke)

    assert handled, "extend_api should return the plugin's result"
    assert_equal [invoke], target.invokes
    assert_empty other.invokes, "only the named plugin should receive the invoke"
  end

  def test_extend_api_returns_plugin_result_when_unhandled
    store = Tokra::PluginStore.new
    store.register(RecordingPlugin.new(handles: false))

    refute store.extend_api("recording", build_invoke("unknown")),
      "extend_api should return false when the plugin does not handle the command"
  end

  def test_extend_api_rejects_unknown_plugin
    store = Tokra::PluginStore.new

    rejected_message = nil
    invoke = build_invoke("greet",
      responder: -> (success, value) { rejected_message = value unless success })
    handled = store.extend_api("missing", invoke)

    assert handled, "extend_api should return true after rejecting an unknown plugin"
    assert_equal "plugin missing not found", rejected_message,
      "should reject with Tauri's plugin-not-found message"
  end

  def test_on_event_reaches_every_plugin
    store = Tokra::PluginStore.new
    first = RecordingPlugin.new(name: "first")
    second = RecordingPlugin.new(name: "second")
    store.register(first)
    store.register(second)

    app = Object.new
    event = Tokra::RunEvent::Exit.new
    store.on_event(app, event)

    assert_equal [[app, event]], first.events, "first plugin should receive the app and event"
    assert_equal [[app, event]], second.events, "second plugin should receive the app and event"
  end

  private def build_invoke(command, responder: nil)
    Tokra::Invoke.new(command:, payload: {}, responder:, webview: nil)
  end
end
