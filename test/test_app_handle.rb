# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::AppHandle manager methods.
class TestAppHandle < Minitest::Test
  private def create_handle
    config = Tokra::Config.new(identifier: "test", product_name: "Test", version: "1.0")
    manager = Tokra::AppManager.new(config:, webviews: {}, windows: {})
    Tokra::AppHandle.new(manager)
  end

  # Named plugin recording extend_api calls.
  class GreetPlugin < Tokra::Plugin
    attr_reader :invokes

    def initialize(app = nil, config = {})
      super
      @invokes = []
    end

    def name = "greet"

    def extend_api(invoke)
      @invokes << invoke
      true
    end
  end

  def test_plugin_registers_for_ipc_dispatch
    handle = create_handle
    plugin = GreetPlugin.new

    replaced = handle.plugin(plugin)

    refute replaced, "plugin should return false when nothing was replaced"
    invoke = Tokra::Ipc::Invoke.new(command: "hello", payload: {}, responder: nil, webview: nil)
    assert handle.__send__(:manager).plugins.extend_api("greet", invoke)
    assert_equal [invoke], plugin.invokes, "registered plugin should receive invokes"
  end

  def test_remove_plugin_unregisters
    handle = create_handle
    handle.plugin(GreetPlugin.new)

    assert handle.remove_plugin("greet"), "remove_plugin should return true when removed"
    refute handle.remove_plugin("greet"), "remove_plugin should return false when absent"
  end

  def test_resources_table_returns_resource_table
    handle = create_handle
    assert_instance_of Tokra::ResourceTable, handle.resources_table
  end

  def test_resources_table_is_memoized
    handle = create_handle
    table1 = handle.resources_table
    table2 = handle.resources_table
    assert_same table1, table2, "resources_table should return same instance"
  end

  def test_windows_returns_windows_hash
    config = Tokra::Config.new(identifier: "test", product_name: "Test", version: "1.0")
    windows = { "main" => Object.new }
    manager = Tokra::AppManager.new(config:, webviews: {}, windows:)
    handle = Tokra::AppHandle.new(manager)

    assert_equal windows, handle.windows
  end

  def test_get_window_returns_window_by_label
    config = Tokra::Config.new(identifier: "test", product_name: "Test", version: "1.0")
    window = Object.new
    windows = { "main" => window }
    manager = Tokra::AppManager.new(config:, webviews: {}, windows:)
    handle = Tokra::AppHandle.new(manager)

    assert_same window, handle.get_window("main")
  end

  def test_get_window_returns_nil_for_unknown_label
    handle = create_handle
    assert_nil handle.get_window("unknown")
  end

  # Counter state for manage tests.
  class Counter
    attr_reader :count

    def initialize(count) = @count = count
  end

  def test_manage_stores_state_and_returns_true
    handle = Tokra::AppHandle.new(create_handle.__send__(:manager), state_manager: Tokra::StateManager.new)
    first = Counter.new(1)

    assert_equal true, handle.manage(first), "the first instance of a class is stored"
    assert_same first, handle.state(Counter)
  end

  def test_manage_keeps_the_first_instance_and_returns_false
    handle = Tokra::AppHandle.new(create_handle.__send__(:manager), state_manager: Tokra::StateManager.new)
    first = Counter.new(1)
    handle.manage(first)

    assert_equal false, handle.manage(Counter.new(2)), "Tauri returns false when T is already managed"
    assert_same first, handle.state(Counter), "the first instance stays managed"
  end

  def test_manage_without_state_manager_raises
    error = assert_raises(Tokra::Error) { create_handle.manage(Counter.new(1)) }
    assert_equal "No StateManager available", error.message
  end

  def test_built_app_handle_manages_through_the_builder_state
    require_relative "support/stub_native"
    app = Tokra::Builder.default.build(native: StubNative)

    assert app.handle.manage(Counter.new(3))
    assert_equal 3, app.handle.state(Counter).count
  end
end
