# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for the Plugin base class.
#
# These tests verify that the base class provides sensible defaults
# matching Tauri's Plugin trait, where only +name+ is required.
class TestPlugin < Minitest::Test
  def test_on_event_returns_nil_by_default
    plugin = Tokra::Plugin.allocate
    assert_nil plugin.on_event(:app, :some_event)
  end

  def test_window_created_returns_nil_by_default
    plugin = Tokra::Plugin.allocate
    assert_nil plugin.window_created(:window)
  end

  def test_webview_created_returns_nil_by_default
    plugin = Tokra::Plugin.allocate
    assert_nil plugin.webview_created(:webview)
  end

  def test_initialize_provides_app_and_config_to_subclasses
    captured_app = nil
    captured_config = nil

    subclass = Class.new(Tokra::Plugin) do
      define_method(:initialize) do |app, config|
        super(app, config)
        captured_app = self.app
        captured_config = self.config
      end
    end

    app = Object.new
    config = { foo: "bar" }
    subclass.new(app, config)

    assert_equal app, captured_app
    assert_equal config, captured_config
  end

  def test_on_navigation_returns_true_by_default
    plugin = Tokra::Plugin.allocate
    # True allows navigation; false would block all navigation
    assert_equal true, plugin.on_navigation(:webview, "http://example.com")
  end

  def test_extend_api_returns_false_by_default
    plugin = Tokra::Plugin.allocate
    # False means "not handled, pass to next handler"
    assert_equal false, plugin.extend_api(:invoke)
  end
end
