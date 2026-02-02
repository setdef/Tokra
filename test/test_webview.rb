# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Webview.
class TestWebview < Minitest::Test
  def test_new_with_label_and_native
    native = Object.new
    window = Object.new
    app_handle = Object.new
    webview = Tokra::Webview.new(label: "main", native:, window:, app_handle:)

    assert_equal "main", webview.label
  end

  def test_window_returns_parent
    window = Object.new
    webview = Tokra::Webview.new(label: "wv", native: Object.new, window:, app_handle: Object.new)

    assert_same window, webview.window
  end

  def test_resources_table_returns_resource_table
    webview = Tokra::Webview.new(label: "wv", native: Object.new, window: Object.new, app_handle: Object.new)
    assert_instance_of Tokra::ResourceTable, webview.resources_table
  end

  def test_eval_delegates_to_native
    native = Minitest::Mock.new
    native.expect :eval, nil, ["console.log('hi')"]
    webview = Tokra::Webview.new(label: "wv", native:, window: Object.new, app_handle: Object.new)

    webview.eval("console.log('hi')")

    native.verify
  end
end
