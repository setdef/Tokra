# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
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

  # Minimal app handle standing in for AppHandle#manage.
  class StubApp
    attr_reader :managed

    def initialize
      @managed = []
    end

    def manage(state)
      @managed << state
    end
  end

  private def build_plugin
    Tokra::Plugins::Clipboard::Plugin.new(StubApp.new)
  end

  private def stub_webview
    Tokra::Webview.new(label: "test", native: Object.new, window: Object.new, app_handle: Object.new)
  end

  private def build_invoke(command, payload = {}, webview: stub_webview)
    responses = []
    invoke = Tokra::Invoke.new(
      command:,
      payload:,
      webview:,
      responder: -> (success, value) { responses << [success, value] }
    )
    [invoke, responses]
  end

  # Plugin name must match Tauri's "clipboard-manager" per ADR-008
  def test_name_returns_clipboard_manager
    assert_equal "clipboard-manager", build_plugin.name
  end

  def test_initialize_manages_native_clipboard
    app = StubApp.new
    Tokra::Plugins::Clipboard::Plugin.new(app)

    # Registration stores the native clipboard in managed state, the body
    # of Tauri's setup closure (clipboard-manager lib.rs)
    assert_equal 1, app.managed.size
    assert_instance_of TokraClipboard::Native::Clipboard, app.managed.first
  end

  def test_native_clipboard_is_ractor_shareable_when_frozen
    # Per ADR-007, native clipboard can be made shareable via Ractor.make_shareable
    native = TokraClipboard::Native::Clipboard.new
    Ractor.make_shareable(native)
    assert Ractor.shareable?(native), "Native clipboard should be Ractor-shareable when frozen"
  end

  def test_write_and_read_roundtrip
    plugin = build_plugin
    plugin.write_text("test_clipboard_roundtrip")
    assert_equal "test_clipboard_roundtrip", plugin.read_text
  end

  def test_clear_empties_clipboard
    plugin = build_plugin
    plugin.write_text("to_be_cleared")
    plugin.clear
    # After clear, read_text raises Error::Clipboard with arboard's
    # message, matching Tauri's rejected promise (desktop.rs read_text
    # propagates get_text errors into Error::Clipboard)
    error = assert_raises(Tokra::Plugins::Clipboard::Error::Clipboard) { plugin.read_text }
    assert_equal EMPTY_CLIPBOARD_MESSAGE, error.message
    assert_kind_of Tokra::Error, error, "plugin errors should remain rescuable as Tokra::Error"
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

  def test_plugin_image_roundtrip_through_tokra_image
    plugin = build_plugin
    image = Tokra::Image.new(rgba: RGBA_2X2, width: 2, height: 2)

    plugin.write_image(image)
    read = plugin.read_image

    assert_instance_of Tokra::Image, read
    assert_equal image, read, "Image should round-trip through the clipboard byte-exact"
  end

  def test_extend_api_read_text_dispatch
    # The router strips plugin:clipboard-manager|, so commands are bare
    plugin = build_plugin
    plugin.write_text("ipc_test_value")

    invoke, responses = build_invoke("read_text")
    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true for handled command"
    assert_equal [[true, "ipc_test_value"]], responses
  end

  def test_extend_api_read_text_rejects_when_empty
    plugin = build_plugin
    plugin.clear

    invoke, responses = build_invoke("read_text")
    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true after rejecting"
    assert_equal [[false, EMPTY_CLIPBOARD_MESSAGE]], responses,
      "empty clipboard should reject with arboard's message, like Tauri"
  end

  def test_extend_api_write_text_dispatch
    plugin = build_plugin

    invoke, responses = build_invoke("write_text", { "text" => "written_via_ipc" })
    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true for handled command"
    assert_equal [[true, nil]], responses
    assert_equal "written_via_ipc", plugin.read_text
  end

  def test_extend_api_read_image_resolves_rid
    plugin = build_plugin
    plugin.write_image(Tokra::Image.new(rgba: RGBA_2X2, width: 2, height: 2))
    webview = stub_webview

    invoke, responses = build_invoke("read_image", {}, webview:)
    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true for handled command"
    success, rid = responses.first
    assert success, "read_image should resolve"
    assert_kind_of Integer, rid, "read_image should resolve a resource ID"

    stored = webview.resources_table.get(rid)
    assert_instance_of Tokra::Image, stored, "the webview table should hold the image"
    assert_equal RGBA_2X2, stored.rgba
  end

  def test_extend_api_write_image_with_rid
    plugin = build_plugin
    webview = stub_webview
    rid = webview.resources_table.add(Tokra::Image.new(rgba: RGBA_2X2, width: 2, height: 2))

    invoke, responses = build_invoke("write_image", { "image" => rid }, webview:)
    result = plugin.extend_api(invoke)

    assert result
    assert_equal [[true, nil]], responses
    assert_equal RGBA_2X2, plugin.read_image.rgba, "the referenced image should reach the clipboard"
  end

  def test_extend_api_write_image_with_rgba_hash
    plugin = build_plugin

    payload = { "image" => { "rgba" => RGBA_2X2.bytes, "width" => 2, "height" => 2 } }
    invoke, responses = build_invoke("write_image", payload)
    result = plugin.extend_api(invoke)

    assert result
    assert_equal [[true, nil]], responses
    assert_equal RGBA_2X2, plugin.read_image.rgba
  end

  def test_extend_api_write_image_with_unknown_rid_rejects
    plugin = build_plugin

    invoke, responses = build_invoke("write_image", { "image" => 999 })
    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true after rejecting"
    success, message = responses.first
    refute success
    assert_equal "The resource id 999 is invalid.", message
  end

  def test_extend_api_write_image_with_invalid_type_rejects
    plugin = build_plugin

    invoke, responses = build_invoke("write_image", { "image" => true })
    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true after rejecting"
    success, message = responses.first
    refute success
    assert_match(/invalid args: image/, message)
  end

  def test_extend_api_write_html_uses_camel_case_alt_text
    plugin = build_plugin

    invoke, responses = build_invoke("write_html", { "html" => "<b>via ipc</b>", "altText" => "via ipc" })
    result = plugin.extend_api(invoke)

    assert result
    assert_equal [[true, nil]], responses
    assert_equal "via ipc", plugin.read_text,
      "the wire's camelCase altText should become the plain-text flavor"
  end

  def test_extend_api_clear_dispatch
    plugin = build_plugin
    plugin.write_text("to_be_cleared_via_ipc")

    invoke, responses = build_invoke("clear")
    result = plugin.extend_api(invoke)

    assert result
    assert_equal [[true, nil]], responses
    assert_raises(Tokra::Plugins::Clipboard::Error::Clipboard) { plugin.read_text }
  end

  def test_extend_api_unknown_command_returns_false
    plugin = build_plugin
    invoke, responses = build_invoke("unknown")

    refute plugin.extend_api(invoke), "extend_api should return false for unknown command"
    assert_empty responses, "unknown commands should not resolve or reject"
  end

  def test_on_event_exit_cleans_up_native_clipboard
    plugin = build_plugin

    plugin.on_event(StubApp.new, Tokra::RunEvent::Exit.new)

    error = assert_raises(Tokra::Plugins::Clipboard::Error::Clipboard) { plugin.read_text }
    assert_match(/cleaned up/i, error.message)
  end

  def test_on_event_ignores_other_events
    plugin = build_plugin
    plugin.write_text("survives_ready")

    plugin.on_event(StubApp.new, Tokra::RunEvent::Ready.new)

    assert_equal "survives_ready", plugin.read_text, "non-Exit events should not clean up"
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
