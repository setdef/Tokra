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
end
