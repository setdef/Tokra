# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "tokra-clipboard"

# Tokra's StubNative double lives with the core tests; plugins exercise a
# real AppHandle built on it instead of a hand-rolled stand-in.
$LOAD_PATH.unshift File.expand_path("../../../test", __dir__)
require "support/stub_native"

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

  # A real app handle, built exactly as an app builds one.
  private def build_app
    Tokra::Builder.default.build(native: StubNative)
  end

  private def build_plugin(app = build_app)
    Tokra::Plugins::Clipboard::Plugin.new(app.handle)
  end

  private def stub_webview
    Tokra::Webview.new(label: "test", native: Object.new, window: Object.new, app_handle: Object.new)
  end

  private def build_invoke(command, payload = {}, webview: stub_webview)
    responses = []
    invoke = Tokra::Ipc::Invoke.new(
      command:,
      payload:,
      webview:,
      responder: -> (success, value) { responses << [success, JSON.parse(value)] }
    )
    [invoke, responses]
  end

  # Plugin name must match Tauri's "clipboard-manager" per ADR-008
  def test_name_returns_clipboard_manager
    assert_equal "clipboard-manager", build_plugin.name
  end

  def test_registering_on_a_real_handle_manages_the_native_clipboard
    app = build_app
    plugin = Tokra::Plugins::Clipboard::Plugin.new(app.handle)
    app.handle.plugin(plugin)

    # Registration stores the native clipboard in managed state, the body
    # of Tauri's setup closure (clipboard-manager lib.rs:54-61)
    assert_instance_of TokraClipboard::Native::Clipboard, app.handle.clipboard
    assert Ractor.shareable?(app.handle.clipboard), "the managed clipboard is Ractor-shareable"
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
    assert_equal [[false, "invalid args `image` for command `write_image`: #{Tokra::JsImage::MISMATCH}"]],
      responses
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
    app = build_app
    plugin = build_plugin(app)

    plugin.on_event(app.handle, Tokra::RunEvent::Exit.new)

    error = assert_raises(Tokra::Plugins::Clipboard::Error::Clipboard) { plugin.read_text }
    assert_match(/cleaned up/i, error.message)
  end

  def test_on_event_ignores_other_events
    app = build_app
    plugin = build_plugin(app)
    plugin.write_text("survives_ready")

    plugin.on_event(app.handle, Tokra::RunEvent::Ready.new)

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

  # ==========================================================================
  # Managed state (Plan 016 #4, #9)
  # ==========================================================================

  # A second plugin finds a clipboard already managed (manage returns
  # false) and must share it, so Exit cleans the one everything uses.
  def test_second_plugin_shares_the_managed_clipboard
    app = build_app
    first = build_plugin(app)
    managed = app.handle.clipboard
    second = build_plugin(app)

    assert_same managed, app.handle.clipboard, "the first clipboard stays managed"
    second.write_text("shared")
    assert_equal "shared", first.read_text

    second.on_event(app.handle, Tokra::RunEvent::Exit.new)
    error = assert_raises(Tokra::Plugins::Clipboard::Error::Clipboard) { first.read_text }
    assert_match(/cleaned up/i, error.message, "Exit cleans app.clipboard, the managed one")
  end

  def test_exit_through_a_real_run_cleans_the_managed_clipboard
    app = build_app
    app.handle.plugin(build_plugin(app))

    app.run

    error = assert_raises(RuntimeError) { app.handle.clipboard.read_text }
    assert_match(/cleaned up/i, error.message, "the run's final Exit reaches the plugin")
  ensure
    StubNative.clear_event
  end

  # ==========================================================================
  # Zero-size images (Plan 016 #6)
  # ==========================================================================

  CONVERSION_FAILURE =
    "The image or the text that was about the be transferred to/from the clipboard " \
      "could not be converted to the appropriate format."

  # arboard's macOS backend panics (uncatchable fatal) on these shapes.
  def test_write_image_rejects_zero_dimensions_with_conversion_failure
    native = TokraClipboard::Native::Clipboard.new
    [[0, 0], [0, 1], [1, 0]].each do |width, height|
      error = assert_raises(RuntimeError, "#{width}x#{height}") { native.write_image("".b, width, height) }
      assert_equal CONVERSION_FAILURE, error.message
    end
  end

  def test_write_image_rejects_zero_width_with_bytes
    native = TokraClipboard::Native::Clipboard.new
    error = assert_raises(RuntimeError) { native.write_image(RGBA_2X2, 0, 4) }
    assert_equal CONVERSION_FAILURE, error.message
  end

  def test_cleaned_up_clipboard_reports_its_own_error_before_the_shape
    native = TokraClipboard::Native::Clipboard.new
    native.cleanup
    error = assert_raises(RuntimeError) { native.write_image("".b, 0, 0) }
    assert_equal "Clipboard has been cleaned up", error.message
  end

  def test_zero_size_image_over_ipc_rejects
    plugin = build_plugin
    invoke, responses = build_invoke("write_image", { "image" => { "rgba" => [], "width" => 0, "height" => 0 } })

    assert plugin.extend_api(invoke)
    assert_equal [[false, CONVERSION_FAILURE]], responses
  end

  # ==========================================================================
  # Non-square images: swapping width and height must fail
  # ==========================================================================

  FIXTURES = File.expand_path("../../../test/fixtures", __dir__)
  RED_THEN_BLUE = "\xFF\x00\x00\xFF\x00\x00\xFF\xFF".b

  def test_non_square_image_round_trips_with_its_dimensions
    native = TokraClipboard::Native::Clipboard.new
    native.write_image(RED_THEN_BLUE, 2, 1)

    assert_equal [RED_THEN_BLUE, 2, 1], native.read_image, "width 2, height 1, not 1 by 2"
  end

  def test_write_image_ipc_with_png_path
    plugin = build_plugin
    invoke, responses = build_invoke("write_image", { "image" => File.join(FIXTURES, "2x1.png") })

    assert plugin.extend_api(invoke)
    assert_equal [[true, nil]], responses
    assert_equal Tokra::Image.new(rgba: RED_THEN_BLUE, width: 2, height: 1), plugin.read_image
  end

  def test_write_image_ipc_with_png_byte_array
    plugin = build_plugin
    bytes = File.binread(File.join(FIXTURES, "2x1.png")).bytes
    invoke, responses = build_invoke("write_image", { "image" => bytes })

    assert plugin.extend_api(invoke)
    assert_equal [[true, nil]], responses
    assert_equal Tokra::Image.new(rgba: RED_THEN_BLUE, width: 2, height: 1), plugin.read_image
  end

  def test_write_image_ipc_with_missing_png_path_rejects
    plugin = build_plugin
    invoke, responses = build_invoke("write_image", { "image" => File.join(FIXTURES, "absent.png") })

    assert plugin.extend_api(invoke)
    success, message = responses.first
    refute success
    assert_match(/No such file or directory/, message)
  end

  # ==========================================================================
  # Argument validation (Plan 016 #7): Tauri's InvalidArgs wording
  # ==========================================================================

  {
    ["write_text", {}] => "invalid args `text` for command `write_text`: command write_text missing required key text",
    ["write_text", { "text" => nil }] => "invalid args `text` for command `write_text`: invalid type: null, expected a borrowed string",
    ["write_text", { "text" => 5 }] => "invalid args `text` for command `write_text`: invalid type: integer `5`, expected a borrowed string",
    ["write_text", { "text" => 1.5 }] => "invalid args `text` for command `write_text`: invalid type: floating point `1.5`, expected a borrowed string",
    ["write_text", { "text" => true }] => "invalid args `text` for command `write_text`: invalid type: boolean `true`, expected a borrowed string",
    ["write_text", { "text" => [] }] => "invalid args `text` for command `write_text`: invalid type: sequence, expected a borrowed string",
    ["write_text", { "text" => {} }] => "invalid args `text` for command `write_text`: invalid type: map, expected a borrowed string",
    ["write_html", {}] => "invalid args `html` for command `write_html`: command write_html missing required key html",
    ["write_html", { "html" => "<b>x</b>", "altText" => 5 }] => "invalid args `altText` for command `write_html`: invalid type: integer `5`, expected a borrowed string",
    ["write_image", {}] => "invalid args `image` for command `write_image`: command write_image missing required key image",
    ["write_image", { "image" => { "rgba" => [], "width" => -1, "height" => 1 } }] => "invalid args `image` for command `write_image`: data did not match any variant of untagged enum JsImage",
    ["write_image", { "image" => { "rgba" => [256, 0, 0, 0], "width" => 1, "height" => 1 } }] => "invalid args `image` for command `write_image`: data did not match any variant of untagged enum JsImage",
  }.each_with_index do |((command, payload), message), index|
    define_method(:"test_invalid_args_#{command}_#{index}_reject_instead_of_raising") do
      plugin = build_plugin
      invoke, responses = build_invoke(command, payload)

      assert plugin.extend_api(invoke), "a bad argument is handled, not raised"
      assert_equal [[false, message]], responses
    end
  end

  def test_write_html_accepts_null_alt_text
    plugin = build_plugin
    invoke, responses = build_invoke("write_html", { "html" => "<i>x</i>", "altText" => nil })

    assert plugin.extend_api(invoke)
    assert_equal [[true, nil]], responses, "Option<&str> treats null as None"
  end

  # Tauri desktop still deserializes label as Option<String>, so a
  # non-string label rejects before the text is written.
  def test_write_text_rejects_a_non_string_label
    plugin = build_plugin
    plugin.write_text("before")
    invoke, responses = build_invoke("write_text", { "text" => "after", "label" => 42 })

    assert plugin.extend_api(invoke)
    assert_equal [[false, "invalid args `label` for command `write_text`: invalid type: integer `42`, expected a string"]],
      responses
    assert_equal "before", plugin.read_text, "a rejected invoke writes nothing"
  end

  def test_write_text_accepts_a_null_label
    plugin = build_plugin
    invoke, responses = build_invoke("write_text", { "text" => "unlabelled", "label" => nil })

    assert plugin.extend_api(invoke)
    assert_equal [[true, nil]], responses
  end

  def test_write_text_ignores_the_mobile_label
    plugin = build_plugin
    invoke, responses = build_invoke("write_text", { "text" => "labelled", "label" => "work" })

    assert plugin.extend_api(invoke)
    assert_equal [[true, nil]], responses
    assert_equal "labelled", plugin.read_text
  end

  # ==========================================================================
  # Packaging (Plan 016 #1, #8)
  # ==========================================================================

  def test_crate_states_its_own_lints_for_an_installed_gem
    manifest = File.read(File.expand_path("../ext/tokra_clipboard/Cargo.toml", __dir__))

    refute_match(/^\s*workspace\s*=\s*true/, manifest, "an installed gem has no workspace to inherit from")
    assert_includes manifest, "[lints.clippy]"
  end

  def test_native_load_error_propagates_with_its_real_message
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "tokra_clipboard"))
      File.write(File.join(dir, "tokra_clipboard", "tokra_clipboard.rb"),
        'raise LoadError, "dlopen failed: image not found"')
      lib = File.expand_path("../lib", __dir__)
      script = 'begin; require "tokra/plugins/clipboard"; rescue LoadError => e; print e.message; end'
      output = IO.popen([RbConfig.ruby, "-I", dir, "-I", lib, "-e", script], err: [:child, :out], &:read)

      assert_equal "dlopen failed: image not found", output, "the real failure surfaces, not a later NameError"
    end
  end
end
