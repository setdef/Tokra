# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Resource mixin module.
class TestResource < Minitest::Test
  def test_name_returns_class_name
    resource = Class.new { include Tokra::Resource }.new
    assert_match(/Class/, resource.name, "Default name should include the class name")
  end

  def test_close_returns_nil
    resource = Class.new { include Tokra::Resource }.new
    assert_nil resource.close, "Default close should return nil"
  end

  def test_name_can_be_overridden
    resource_class = Class.new do
      include Tokra::Resource
      def name = "CustomName"
    end
    assert_equal "CustomName", resource_class.new.name, "name should be overridable"
  end

  def test_close_can_be_overridden
    closed = false
    resource_class = Class.new do
      include Tokra::Resource
      define_method(:close) { closed = true }
    end
    resource_class.new.close
    assert closed, "close should be overridable and called"
  end
end
