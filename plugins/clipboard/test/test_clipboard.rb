# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-clipboard"

# Tests for Tokra::Plugins::Clipboard::Plugin.
#
# The construction-error arm (arboard failing in Clipboard.new, e.g. on a
# clipboard-less system) is not testable on a machine with a working
# clipboard; it is verified by review against desktop.rs:11-19.
class TestClipboard < Minitest::Test
  # Same 16 bytes as core's test/fixtures/2x2_rgba.bin: red, green, blue, white.
  RGBA_2X2 = "\xFF\x00\x00\xFF\x00\xFF\x00\xFF\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF".b

  # arboard's ContentNotAvailable message — also what Tauri's rejected
  # promise carries, since Error::Clipboard(String) formats as "{0}".
  EMPTY_CLIPBOARD_MESSAGE =
    "The clipboard contents were not available in the requested format or the clipboard is empty."

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
    # After clear, read_text raises arboard's message, matching Tauri's
    # rejected promise (desktop.rs read_text propagates get_text errors)
    error = assert_raises(RuntimeError) { plugin.read_text }
    assert_equal EMPTY_CLIPBOARD_MESSAGE, error.message
  end

  def test_cleanup_prevents_further_use
    # cleanup() drops the native clipboard; further operations should raise
    native = TokraClipboard::Native::Clipboard.new
    native.cleanup
    error = assert_raises(RuntimeError) { native.read_text }
    assert_match(/cleaned up/i, error.message)
  end

  def test_write_and_read_image_roundtrip
    native = TokraClipboard::Native::Clipboard.new
    native.write_image(RGBA_2X2, 2, 2)

    rgba, width, height = native.read_image

    assert_equal 2, width
    assert_equal 2, height
    assert_equal RGBA_2X2, rgba
  end

  def test_read_image_raises_when_no_image
    native = TokraClipboard::Native::Clipboard.new
    native.clear
    error = assert_raises(RuntimeError) { native.read_image }
    assert_equal EMPTY_CLIPBOARD_MESSAGE, error.message
  end

  def test_write_image_with_wrong_byte_count_raises
    native = TokraClipboard::Native::Clipboard.new
    # The native layer raises arboard's ConversionFailure message; arboard
    # 3.6.1's macOS backend would panic (aborting the VM) on the mismatch
    error = assert_raises(RuntimeError) { native.write_image("\xFF".b, 2, 2) }
    assert_match(/could not be converted/, error.message)
  end

  def test_write_html_sets_alt_text_as_plain_text
    native = TokraClipboard::Native::Clipboard.new
    native.write_html("<b>hi</b>", "hi")
    # arboard writes alt_text as the plain-text flavor; reading it back
    # verifies the write without a read-html API (arboard has none)
    assert_equal "hi", native.read_text
  end

  def test_read_image_rejects_after_cleanup
    native = TokraClipboard::Native::Clipboard.new
    native.cleanup
    error = assert_raises(RuntimeError) { native.read_image }
    assert_match(/cleaned up/i, error.message)
  end

  def test_write_image_rejects_after_cleanup
    native = TokraClipboard::Native::Clipboard.new
    native.cleanup
    error = assert_raises(RuntimeError) { native.write_image(RGBA_2X2, 2, 2) }
    assert_match(/cleaned up/i, error.message)
  end

  def test_write_html_rejects_after_cleanup
    native = TokraClipboard::Native::Clipboard.new
    native.cleanup
    error = assert_raises(RuntimeError) { native.write_html("<b>hi</b>", "hi") }
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
