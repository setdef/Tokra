# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/test_app"

# Tests Tokra::Plugin::Builder and the Tokra::Plugin::TauriPlugin it
# builds, Tauri's plugin::Builder and TauriPlugin (plugin.rs:181-853).
class TestTauriPlugin < Minitest::Test
  def test_build_answers_a_tauri_plugin_with_the_name
    plugin = Tokra::Plugin::Builder.new("example").build

    assert_instance_of Tokra::Plugin::TauriPlugin, plugin
    assert_kind_of Tokra::Plugin, plugin
    assert_equal "example", plugin.name
  end

  def test_reserved_names_are_refused
    %w[core tauri].each do |name|
      error = assert_raises(Tokra::Plugin::BuilderError::ReservedName) { Tokra::Plugin::Builder.new(name).try_build }

      assert_equal "plugin uses reserved name: #{name}", error.message, "plugin.rs:185-190"
      assert_equal name, error.name
      assert_raises(Tokra::Plugin::BuilderError::ReservedName) { Tokra::Plugin::Builder.new(name).build }
    end
    assert_kind_of Tokra::Error, Tokra::Plugin::BuilderError::ReservedName.new("core")
  end

  def test_the_defaults_are_tauris
    plugin = Tokra::Plugin::Builder.new("example").build

    refute plugin.extend_api(:invoke), "invoke_handler defaults to |_| false (plugin.rs:285)"
    assert plugin.on_navigation(:webview, :url), "on_navigation defaults to true (plugin.rs:286)"
    assert_nil plugin.initialization_script
    assert_nil plugin.initialization_script_2
  end

  def test_each_hook_calls_its_block
    calls = []
    plugin = Tokra::Plugin::Builder.new("example")
      .invoke_handler { |invoke| calls << [:invoke, invoke] }
      .on_navigation { |webview, url| (calls << [:navigation, webview, url]) && false }
      .on_page_load { |webview, payload| calls << [:page_load, webview, payload] }
      .on_window_ready { |window| calls << [:window, window] }
      .on_webview_ready { |webview| calls << [:webview, webview] }
      .on_event { |app, event| calls << [:event, app, event] }
      .build

    assert plugin.extend_api(:i)
    refute plugin.on_navigation(:w, :u)
    plugin.on_page_load(:w, :p)
    plugin.window_created(:win)
    plugin.webview_created(:wv)
    plugin.on_event(:app, :e)

    assert_equal [
      [:invoke, :i],
      [:navigation, :w, :u],
      [:page_load, :w, :p],
      [:window, :win],
      [:webview, :wv],
      [:event, :app, :e],
], calls, "plugin.rs:830-852"
  end

  def test_js_init_script_is_for_the_main_frame
    plugin = Tokra::Plugin::Builder.new("example").js_init_script("one").build

    assert_equal "one", plugin.initialization_script
    assert_equal ["one", true], plugin.initialization_script_2
  end

  def test_js_init_script_on_all_frames_replaces_and_reaches_every_frame
    plugin = Tokra::Plugin::Builder.new("example").js_init_script("one").js_init_script_on_all_frames("two").build

    assert_equal "two", plugin.initialization_script
    assert_equal ["two", false], plugin.initialization_script_2
  end

  def test_setup_runs_once
    runs = 0
    plugin = Tokra::Plugin::Builder.new("example").setup { |_app, _api| runs += 1 }.build
    handle = Tokra::AppHandle.new(build_test_manager)

    plugin.initialize_plugin(handle, nil)
    plugin.initialize_plugin(handle, nil)

    assert_equal 1, runs, "setup is taken as it runs (plugin.rs:793)"
  end

  def test_a_later_setup_replaces_an_earlier_one
    ran = []
    plugin = Tokra::Plugin::Builder.new("example")
      .setup { |_app, _api| ran << :first }
      .setup { |_app, _api| ran << :second }
      .build

    plugin.initialize_plugin(Tokra::AppHandle.new(build_test_manager), nil)

    assert_equal [:second], ran
  end

  def test_the_unit_config_message_names_each_kind_of_value
    {
      true => "boolean `true`",
      1 => "integer `1`",
      1.5 => "floating point `1.5`",
      "x" => 'string "x"',
      [] => "sequence",
    }.each do |value, unexpected|
      plugin = Tokra::Plugin::Builder.new("example").setup { |_app, _api| nil }.build
      error = assert_raises(Tokra::Error) { plugin.initialize_plugin(Tokra::AppHandle.new(build_test_manager), value) }

      assert_equal "Error deserializing 'plugins.example' within your Tokra configuration: invalid type: " \
        "#{unexpected}, expected unit", error.message
    end
  end

  def test_a_config_type_reads_the_slice_and_its_error_is_wrapped
    type = Module.new do
      def self.deserialize(value)
        raise Tokra::Ipc::CommandItem::Mismatch.invalid_type(value, "a string") unless value.is_a?(String)

        value.upcase
      end
    end
    seen = nil
    plugin = Tokra::Plugin::Builder.new("example", config: type).setup { |_app, api| seen = api.config }.build
    handle = Tokra::AppHandle.new(build_test_manager)

    error = assert_raises(Tokra::Error) { plugin.initialize_plugin(handle, 7) }
    assert_equal "Error deserializing 'plugins.example' within your Tokra configuration: invalid type: integer `7`, " \
      "expected a string", error.message

    other = Tokra::Plugin::Builder.new("example", config: type).setup { |_app, api| seen = api.config }.build
    other.initialize_plugin(handle, "on")
    assert_equal "ON", seen
  end

  def test_on_drop_needs_an_initialized_plugin
    dropped = []
    plugin = Tokra::Plugin::Builder.new("example").on_drop { |app| dropped << app }.build

    plugin.drop

    assert_empty dropped, "Drop runs on_drop only when the plugin has its app (plugin.rs:774-780)"
  end

  def test_blocks_are_required
    builder = Tokra::Plugin::Builder.new("example")

    %i[invoke_handler setup on_navigation on_page_load on_window_ready on_webview_ready on_event on_drop].each do |hook|
      assert_raises(ArgumentError, hook.to_s) { builder.public_send(hook) }
    end
  end
end
