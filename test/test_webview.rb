# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# Tests for Tokra::Webview.
class TestWebview < Minitest::Test
  # A real handle, built on this thread, so this thread is the main thread.
  def app_handle
    @app_handle ||= Tokra::Builder.default.build(native: StubNative).handle
  end

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
    webview = Tokra::Webview.new(label: "wv", native:, window: Object.new, app_handle:)

    webview.eval("console.log('hi')")

    native.verify
  end

  def test_eval_returns_nil
    webview = Tokra::Webview.new(label: "wv", native: StubNative::WebView.new, window: Object.new, app_handle:)

    assert_nil webview.eval("1")
  end
end
