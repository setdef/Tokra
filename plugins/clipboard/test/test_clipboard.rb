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
# Every test drives the real system clipboard through ferro-arboard.
#
# The construction-error arm (arboard failing in Clipboard.new, e.g. on a
# clipboard-less system) is not testable on a machine with a working
# clipboard; it is verified by review against desktop.rs:11-19.
class TestClipboard < Minitest::Test
  # The plugin's managed state, Tauri's desktop.rs Clipboard.
  CLIPBOARD = Tokra::Plugins::Clipboard::Clipboard
  CLIPBOARD_ERROR = Tokra::Plugins::Clipboard::Error::Clipboard
  CLEANED_UP = "Clipboard has been cleaned up"

  # arboard's ConversionFailure message, typo included (common.rs).
  CONVERSION_FAILURE =
    "The image or the text that was about the be transferred to/from the clipboard " \
      "could not be converted to the appropriate format."

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

  def test_registering_on_a_real_handle_manages_the_clipboard
    app = build_app
    plugin = Tokra::Plugins::Clipboard::Plugin.new(app.handle)
    app.handle.plugin(plugin)

    # Registration stores the clipboard in managed state, the body of
    # Tauri's setup closure (clipboard-manager lib.rs:54-61)
    assert_instance_of CLIPBOARD, app.handle.clipboard
    assert Ractor.shareable?(app.handle.clipboard), "the managed clipboard is Ractor-shareable"
  end

  # Per ADR 007 and ADR 011 section 7, the clipboard is born shareable:
  # ferro-arboard's frozen clipboard is, and so is the cleanup latch.
  def test_clipboard_is_ractor_shareable_as_built
    assert Ractor.shareable?(CLIPBOARD.new), "the clipboard should be Ractor-shareable without help"
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
    # cleanup() retires the clipboard; further operations should raise
    clipboard = CLIPBOARD.new
    clipboard.cleanup
    error = assert_raises(CLIPBOARD_ERROR) { clipboard.read_text }
    assert_equal CLEANED_UP, error.message
  end

  def test_cleanup_may_repeat
    clipboard = CLIPBOARD.new
    clipboard.cleanup
    clipboard.cleanup

    assert_raises(CLIPBOARD_ERROR) { clipboard.write_text("after") }
  end

  def test_cleanup_retires_only_its_own_clipboard
    retired = CLIPBOARD.new
    live = CLIPBOARD.new
    retired.cleanup

    live.write_text("still here")
    assert_equal "still here", live.read_text
  end

  def test_write_and_read_image_roundtrip
    clipboard = CLIPBOARD.new
    clipboard.write_image(Tokra::Image.new(rgba: RGBA_2X2, width: 2, height: 2))

    image = clipboard.read_image

    assert_equal 2, image.width
    assert_equal 2, image.height
    assert_equal RGBA_2X2, image.rgba
  end

  def test_read_image_raises_when_no_image
    clipboard = CLIPBOARD.new
    clipboard.clear
    error = assert_raises(CLIPBOARD_ERROR) { clipboard.read_image }
    assert_equal EMPTY_CLIPBOARD_MESSAGE, error.message
  end

  def test_read_image_raises_when_the_clipboard_holds_text
    clipboard = CLIPBOARD.new
    clipboard.write_text("not an image")
    error = assert_raises(CLIPBOARD_ERROR) { clipboard.read_image }
    assert_equal EMPTY_CLIPBOARD_MESSAGE, error.message
  end

  def test_write_image_with_wrong_byte_count_raises
    clipboard = CLIPBOARD.new
    # ferro-arboard raises arboard's ConversionFailure; arboard's macOS
    # backend would panic (aborting the VM) on the mismatch
    error = assert_raises(CLIPBOARD_ERROR) do
      clipboard.write_image(Tokra::Image.new(rgba: "\xFF".b, width: 2, height: 2))
    end
    assert_equal CONVERSION_FAILURE, error.message
  end

  def test_write_html_sets_alt_text_as_plain_text
    clipboard = CLIPBOARD.new
    clipboard.write_html("<b>hi</b>", "hi")
    # arboard writes alt_text as the plain-text flavor; reading it back
    # verifies the write without a read-html API (Tauri has none)
    assert_equal "hi", clipboard.read_text
  end

  def test_read_image_rejects_after_cleanup
    clipboard = CLIPBOARD.new
    clipboard.cleanup
    error = assert_raises(CLIPBOARD_ERROR) { clipboard.read_image }
    assert_equal CLEANED_UP, error.message
  end

  def test_write_image_rejects_after_cleanup
    clipboard = CLIPBOARD.new
    clipboard.cleanup
    error = assert_raises(CLIPBOARD_ERROR) do
      clipboard.write_image(Tokra::Image.new(rgba: RGBA_2X2, width: 2, height: 2))
    end
    assert_equal CLEANED_UP, error.message
  end

  def test_write_html_rejects_after_cleanup
    clipboard = CLIPBOARD.new
    clipboard.cleanup
    error = assert_raises(CLIPBOARD_ERROR) { clipboard.write_html("<b>hi</b>", "hi") }
    assert_equal CLEANED_UP, error.message
  end

  def test_write_text_and_clear_reject_after_cleanup
    clipboard = CLIPBOARD.new
    clipboard.cleanup

    assert_equal CLEANED_UP, assert_raises(CLIPBOARD_ERROR) { clipboard.write_text("x") }.message
    assert_equal CLEANED_UP, assert_raises(CLIPBOARD_ERROR) { clipboard.clear }.message
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
    # ClipboardManagerExt.clipboard returns the clipboard from managed state
    clipboard = CLIPBOARD.new
    mock_manager = Object.new
    mock_manager.define_singleton_method(:state) { |klass| clipboard if klass == CLIPBOARD }
    mock_manager.extend(Tokra::Plugins::Clipboard::ClipboardManagerExt)

    assert_equal clipboard, mock_manager.clipboard
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

    # handle.clipboard is Tauri's app.clipboard(): its errors are the
    # plugin's Error::Clipboard, as in Tauri
    error = assert_raises(CLIPBOARD_ERROR) { app.handle.clipboard.read_text }
    assert_equal CLEANED_UP, error.message, "the run's final Exit reaches the plugin"
  ensure
    StubNative.clear_event
  end

  # ==========================================================================
  # Zero-size images (Plan 016 #6)
  # ==========================================================================

  # arboard's macOS backend panics (uncatchable fatal) on these shapes;
  # ferro-arboard refuses them with ConversionFailure.
  def test_write_image_rejects_zero_dimensions_with_conversion_failure
    clipboard = CLIPBOARD.new
    [[0, 0], [0, 1], [1, 0]].each do |width, height|
      image = Tokra::Image.new(rgba: "".b, width:, height:)
      error = assert_raises(CLIPBOARD_ERROR, "#{width}x#{height}") { clipboard.write_image(image) }
      assert_equal CONVERSION_FAILURE, error.message
    end
  end

  def test_write_image_rejects_zero_width_with_bytes
    clipboard = CLIPBOARD.new
    error = assert_raises(CLIPBOARD_ERROR) { clipboard.write_image(Tokra::Image.new(rgba: RGBA_2X2, width: 0, height: 4)) }
    assert_equal CONVERSION_FAILURE, error.message
  end

  def test_cleaned_up_clipboard_reports_its_own_error_before_the_shape
    clipboard = CLIPBOARD.new
    clipboard.cleanup
    error = assert_raises(CLIPBOARD_ERROR) { clipboard.write_image(Tokra::Image.new(rgba: "".b, width: 0, height: 0)) }
    assert_equal CLEANED_UP, error.message
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
    clipboard = CLIPBOARD.new
    clipboard.write_image(Tokra::Image.new(rgba: RED_THEN_BLUE, width: 2, height: 1))

    assert_equal Tokra::Image.new(rgba: RED_THEN_BLUE, width: 2, height: 1), clipboard.read_image,
      "width 2, height 1, not 1 by 2"
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
    # serde_json describes floats as ryu prints them, and integers past
    # u64 as floats (plan 026, decision 6).
    ["write_text", { "text" => 1e16 }] => "invalid args `text` for command `write_text`: invalid type: floating point `1e16`, expected a borrowed string",
    ["write_text", { "text" => 2 ** 64 }] => "invalid args `text` for command `write_text`: invalid type: floating point `1.8446744073709552e19`, expected a borrowed string",
    ["write_text", { "text" => "x", "label" => 1e300 }] => "invalid args `label` for command `write_text`: invalid type: floating point `1e300`, expected a string",
    ["write_html", {}] => "invalid args `html` for command `write_html`: command write_html missing required key html",
    ["write_html", { "html" => "<b>x</b>", "altText" => 5 }] => "invalid args `altText` for command `write_html`: invalid type: integer `5`, expected a borrowed string",
    ["write_html", { "html" => "<b>x</b>", "altText" => 0.00001 }] => "invalid args `altText` for command `write_html`: invalid type: floating point `0.00001`, expected a borrowed string",
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

  # Only what Tauri's commands return rejects here: an ArgumentError from
  # a bug reaches the router, which logs it before it rejects (plan 026,
  # decision 7).
  def test_an_argument_error_from_a_bug_is_not_taken_for_a_bad_argument
    plugin = build_plugin
    plugin.define_singleton_method(:write_text) { |_text| raise ArgumentError, "a bug" }
    invoke, = build_invoke("write_text", { "text" => "x" })

    assert_equal "a bug", assert_raises(ArgumentError) { plugin.extend_api(invoke) }.message
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
  # Packaging (Plan 016 #8, Plan 021)
  # ==========================================================================

  # The plugin is pure Ruby (ADR 011 section 9): no extension of its own.
  def test_the_gem_ships_no_native_extension
    spec = Gem::Specification.load(File.expand_path("../tokra-clipboard.gemspec", __dir__))

    assert_empty spec.extensions
    assert_includes spec.runtime_dependencies.map(&:name), "ferro-arboard"
  end

  def test_ferro_arboard_load_error_propagates_with_its_real_message
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "ferro"))
      File.write(File.join(dir, "ferro", "arboard.rb"), 'raise LoadError, "dlopen failed: image not found"')
      lib = File.expand_path("../lib", __dir__)
      script = 'begin; require "tokra/plugins/clipboard"; rescue LoadError => e; print e.message; end'
      output = IO.popen([RbConfig.ruby, "-I", dir, "-I", lib, "-e", script], err: [:child, :out], &:read)

      assert_equal "dlopen failed: image not found", output, "the real failure surfaces, not a later NameError"
    end
  end
end
