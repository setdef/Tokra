# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Window.
class TestWindow < Minitest::Test
  def test_new_with_label_and_native
    native = Object.new
    app_handle = Object.new
    window = Tokra::Window.new(label: "main", native:, app_handle:)

    assert_equal "main", window.label
  end

  def test_resources_table_returns_resource_table
    window = Tokra::Window.new(label: "win", native: Object.new, app_handle: Object.new)
    assert_instance_of Tokra::ResourceTable, window.resources_table
  end

  def test_set_title_delegates_to_native
    native = Minitest::Mock.new
    native.expect :set_title, nil, ["My App"]
    window = Tokra::Window.new(label: "win", native:, app_handle: Object.new)

    window.set_title("My App")

    native.verify
  end

  def test_set_size_delegates_to_native
    native = Minitest::Mock.new
    native.expect :set_size, nil, [800.0, 600.0]
    window = Tokra::Window.new(label: "win", native:, app_handle: Object.new)

    window.set_size(800.0, 600.0)

    native.verify
  end
end
