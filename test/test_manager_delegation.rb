# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# Tests that App, Window, and Webview are full Managers, as in Tauri: the
# trait's provided methods reach the one app manager whichever handle you
# hold (lib.rs Manager; app.rs:683, window/mod.rs:987, webview/mod.rs:2256).
class TestManagerDelegation < Minitest::Test
  def setup
    StubNative.clear_event
    @app = Tokra::Builder.default.build(native: StubNative)
    @app.run
    @handle = @app.handle
  end

  def teardown
    StubNative.clear_event
  end

  private def managers
    { "App" => @app, "Window" => @handle.get_window("main"), "Webview" => @handle.get_webview("main") }
  end

  def test_the_run_created_the_window_and_webview
    refute_nil @handle.get_window("main")
    refute_nil @handle.get_webview("main")
  end

  def test_each_manager_manages_state_in_the_apps_state_manager
    managers.each do |kind, manager|
      state_class = Class.new
      state = state_class.new

      assert manager.manage(state), "#{kind}#manage stores new state"
      refute manager.manage(state_class.new), "#{kind}#manage keeps the first value"
      assert_same state, @handle.state(state_class), "#{kind} shares the app's state"
      assert_same state, manager.state(state_class)
      assert_same state, manager.try_state(state_class)
      assert_nil manager.try_state(Class.new)
    end
  end

  def test_each_manager_reads_the_apps_config_windows_and_webviews
    managers.each do |kind, manager|
      assert_same @handle.config, manager.config, kind
      assert_same @handle.get_window("main"), manager.get_window("main"), kind
      assert_same @handle.get_webview("main"), manager.get_webview("main"), kind
      assert_equal @handle.windows, manager.windows, kind
      assert_equal @handle.webviews, manager.webviews, kind
    end
  end

  def test_each_manager_reaches_the_app_handle
    managers.each { |kind, manager| assert_same @handle, manager.app_handle, kind }
  end

  def test_app_shares_the_app_level_resources_table
    assert_same @handle.resources_table, @app.resources_table
    refute_same @handle.resources_table, @handle.get_window("main").resources_table
    refute_same @handle.resources_table, @handle.get_webview("main").resources_table
  end

  def test_app_config_is_the_app_configuration
    assert_instance_of Tokra::Config, @app.config
  end
end
