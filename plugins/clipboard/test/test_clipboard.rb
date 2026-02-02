# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-clipboard"

# Tests for Tokra::Plugins::Clipboard::Plugin.
class TestClipboard < Minitest::Test
  private def stub_webview
    Tokra::Webview.new(label: "test", native: Object.new, window: Object.new, app_handle: Object.new)
  end

  # Plugin name must match Tauri's "clipboard-manager" per ADR-008
  def test_name_returns_clipboard_manager
    plugin = Tokra::Plugins::Clipboard::Plugin.new
    assert_equal "clipboard-manager", plugin.name
  end

  def test_native_clipboard_is_ractor_shareable_when_frozen
    # Per ADR-007, native clipboard can be made shareable via Ractor.make_shareable
    native = TokraClipboard::Native::Clipboard.new
    Ractor.make_shareable(native)
    assert Ractor.shareable?(native), "Native clipboard should be Ractor-shareable when frozen"
  end

  def test_write_and_read_roundtrip
    plugin = Tokra::Plugins::Clipboard::Plugin.new
    plugin.write_text("test_clipboard_roundtrip")
    assert_equal "test_clipboard_roundtrip", plugin.read_text
  end

  def test_clear_empties_clipboard
    plugin = Tokra::Plugins::Clipboard::Plugin.new
    plugin.write_text("to_be_cleared")
    plugin.clear
    # After clear, read_text returns nil
    assert_nil plugin.read_text
  end

  def test_cleanup_prevents_further_use
    # cleanup() drops the native clipboard; further operations should raise
    native = TokraClipboard::Native::Clipboard.new
    native.cleanup
    error = assert_raises(RuntimeError) { native.read_text }
    assert_match(/cleaned up/i, error.message)
  end

  def test_extend_api_read_text_dispatch
    # Verify IPC command is dispatched correctly
    plugin = Tokra::Plugins::Clipboard::Plugin.new
    plugin.write_text("ipc_test_value")

    resolved_value = nil
    responder = -> (success, value) { resolved_value = value if success }
    invoke = Tokra::Invoke.new(
      command: "plugin:clipboard-manager|read_text",
      payload: {},
      responder:,
      webview: stub_webview
    )

    result = plugin.extend_api(invoke)
    assert result, "extend_api should return true for handled command"
    assert_equal "ipc_test_value", resolved_value
  end

  def test_extend_api_write_text_dispatch
    # Verify IPC command writes from payload["text"]
    plugin = Tokra::Plugins::Clipboard::Plugin.new

    resolved = false
    responder = -> (success, _value) { resolved = success }
    invoke = Tokra::Invoke.new(
      command: "plugin:clipboard-manager|write_text",
      payload: { "text" => "written_via_ipc" },
      responder:,
      webview: stub_webview
    )

    result = plugin.extend_api(invoke)
    assert result, "extend_api should return true for handled command"
    assert resolved, "responder should be called with success"
    assert_equal "written_via_ipc", plugin.read_text
  end

  def test_extend_api_unknown_command_returns_false
    # Unknown commands should not be handled
    plugin = Tokra::Plugins::Clipboard::Plugin.new
    invoke = Tokra::Invoke.new(
      command: "plugin:other-plugin|unknown",
      payload: {},
      responder: nil,
      webview: stub_webview
    )

    result = plugin.extend_api(invoke)
    refute result, "extend_api should return false for unknown command"
  end

  def test_manager_extension_provides_clipboard_accessor
    # ClipboardManagerExt.clipboard returns native from managed state
    native = TokraClipboard::Native::Clipboard.new
    mock_manager = Object.new
    mock_manager.define_singleton_method(:state) { |klass| native if klass == TokraClipboard::Native::Clipboard }
    mock_manager.extend(Tokra::Plugins::Clipboard::ClipboardManagerExt)

    assert_equal native, mock_manager.clipboard
  end
end
