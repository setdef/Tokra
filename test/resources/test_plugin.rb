# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Resources::Plugin.
#
# These tests verify that the resources plugin correctly handles the
# plugin:resources|close IPC command with 3-level fallback matching Tauri's
# resources/plugin.rs behavior.
class TestResourcesPlugin < Minitest::Test
  # Test resource implementing the Resource interface.
  class TestResource
    include Tokra::Resource

    attr_reader :closed

    def initialize
      @closed = false
    end

    def close
      @closed = true
      nil
    end
  end

  def test_close_removes_from_webview_table
    plugin = Tokra::Resources::Plugin.new(nil, {})
    webview = build_webview_chain

    # Add resource to webview's table
    resource = TestResource.new
    rid = webview.resources_table.add(resource)

    # Build invoke for plugin:resources|close
    resolved_value = nil
    invoke = Tokra::Invoke.new(
      command: "close",
      payload: { "rid" => rid },
      webview:,
      responder: -> (success, value) { resolved_value = value if success }
    )

    # Plugin should handle the command
    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true for handled command"
    refute webview.resources_table.has?(rid), "resource should be removed from table"
    assert resource.closed, "resource.close should have been called"
    assert_nil resolved_value, "resolve should be called with nil"
  end

  def test_close_falls_back_to_window
    plugin = Tokra::Resources::Plugin.new(nil, {})
    webview = build_webview_chain

    # Add resource to WINDOW's table (not webview)
    resource = TestResource.new
    rid = webview.window.resources_table.add(resource)

    resolved = false
    invoke = Tokra::Invoke.new(
      command: "close",
      payload: { "rid" => rid },
      webview:,
      responder: -> (success, _value) { resolved = success }
    )

    plugin.extend_api(invoke)

    assert resolved, "should resolve successfully via window fallback"
    refute webview.window.resources_table.has?(rid),
      "resource should be removed from window's table"
    assert resource.closed, "resource.close should have been called"
  end

  def test_close_falls_back_to_app_handle
    plugin = Tokra::Resources::Plugin.new(nil, {})
    webview = build_webview_chain

    # Add resource to APP_HANDLE's table (not webview or window)
    resource = TestResource.new
    rid = webview.app_handle.resources_table.add(resource)

    resolved = false
    invoke = Tokra::Invoke.new(
      command: "close",
      payload: { "rid" => rid },
      webview:,
      responder: -> (success, _value) { resolved = success }
    )

    plugin.extend_api(invoke)

    assert resolved, "should resolve successfully via app_handle fallback"
    refute webview.app_handle.resources_table.has?(rid),
      "resource should be removed from app_handle's table"
    assert resource.closed, "resource.close should have been called"
  end

  def test_close_rejects_when_not_found_anywhere
    plugin = Tokra::Resources::Plugin.new(nil, {})
    webview = build_webview_chain

    # Use a rid that doesn't exist in any table
    rejected_message = nil
    invoke = Tokra::Invoke.new(
      command: "close",
      payload: { "rid" => 999_999 },
      webview:,
      responder: -> (success, value) { rejected_message = value unless success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should still return true (command was handled)"
    assert_match(/999999/, rejected_message,
      "should reject with error mentioning the bad rid")
  end

  def test_close_rejects_non_integer_rid
    plugin = Tokra::Resources::Plugin.new(nil, {})
    webview = build_webview_chain

    rejected_message = nil
    invoke = Tokra::Invoke.new(
      command: "close",
      payload: { "rid" => "42" },
      webview:,
      responder: -> (success, value) { rejected_message = value unless success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    assert_equal "invalid args: rid must be an integer", rejected_message
  end

  def test_returns_false_for_other_commands
    plugin = Tokra::Resources::Plugin.new(nil, {})
    invoke = Tokra::Invoke.new(
      command: "new",
      payload: {},
      webview: nil,
      responder: nil
    )

    refute plugin.extend_api(invoke),
      "should return false for commands it doesn't handle"
  end

  private def build_webview_chain
    app_handle = Struct.new(:resources_table).new(Tokra::ResourceTable.new)
    window = Struct.new(:resources_table, :app_handle).new(
      Tokra::ResourceTable.new,
      app_handle
    )
    Struct.new(:resources_table, :window, :app_handle).new(
      Tokra::ResourceTable.new,
      window,
      app_handle
    )
  end
end
