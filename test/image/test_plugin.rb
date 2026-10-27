# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Image::Plugin.
#
# These tests verify that the image plugin correctly handles the
# plugin:image|* IPC commands matching Tauri's image/plugin.rs behavior.
class TestImagePlugin < Minitest::Test
  def test_new_creates_image_in_table
    plugin = Tokra::Image::Plugin.new(nil, {})
    webview = build_webview

    resolved_rid = nil
    invoke = Tokra::Ipc::Invoke.new(
      command: "new",
      payload: {
        "rgba" => [255, 0, 0, 255],
        "width" => 1,
        "height" => 1,
      },
      webview:,
      responder: -> (success, value) { resolved_rid = JSON.parse(value) if success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true for handled command"
    assert_kind_of Integer, resolved_rid, "should resolve with an integer rid"

    # Verify the image was stored in the webview's table
    image = webview.resources_table.get(resolved_rid)
    assert_instance_of Tokra::Image, image, "stored resource should be an Image"
    assert_equal 1, image.width
    assert_equal 1, image.height
  end

  def test_rgba_returns_byte_array
    plugin = Tokra::Image::Plugin.new(nil, {})
    webview = build_webview

    # First, store an image via the new command
    rgba_input = [255, 0, 128, 255]
    new_invoke = Tokra::Ipc::Invoke.new(
      command: "new",
      payload: { "rgba" => rgba_input, "width" => 1, "height" => 1 },
      webview:,
      responder: -> (_, _) {}
    )
    plugin.extend_api(new_invoke)
    rid = webview.resources_table.names.first[0]

    # Now retrieve the rgba bytes
    resolved_value = nil
    rgba_invoke = Tokra::Ipc::Invoke.new(
      command: "rgba",
      payload: { "rid" => rid },
      webview:,
      responder: -> (success, value) { resolved_value = JSON.parse(value) if success }
    )

    result = plugin.extend_api(rgba_invoke)

    assert result, "extend_api should return true"
    assert_equal rgba_input, resolved_value,
      "should resolve with RGBA bytes as integer array"
  end

  def test_size_returns_dimensions
    plugin = Tokra::Image::Plugin.new(nil, {})
    webview = build_webview

    # Store a 3x2 image
    new_invoke = Tokra::Ipc::Invoke.new(
      command: "new",
      payload: { "rgba" => [0] * (3 * 2 * 4), "width" => 3, "height" => 2 },
      webview:,
      responder: -> (_, _) {}
    )
    plugin.extend_api(new_invoke)
    rid = webview.resources_table.names.first[0]

    resolved_value = nil
    size_invoke = Tokra::Ipc::Invoke.new(
      command: "size",
      payload: { "rid" => rid },
      webview:,
      responder: -> (success, value) { resolved_value = JSON.parse(value) if success }
    )

    result = plugin.extend_api(size_invoke)

    assert result, "extend_api should return true"
    assert_equal({ "width" => 3, "height" => 2 }, resolved_value,
      "should resolve with width and height hash")
  end

  def test_rgba_rejects_unknown_rid
    plugin = Tokra::Image::Plugin.new(nil, {})

    rejected_message = nil
    invoke = Tokra::Ipc::Invoke.new(
      command: "rgba",
      payload: { "rid" => 999 },
      webview: build_webview,
      responder: -> (success, value) { rejected_message = JSON.parse(value) unless success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    assert_equal "The resource id 999 is invalid.", rejected_message,
      "bad rid should reject with Tauri's BadResourceId message"
  end

  def test_size_rejects_non_image_resource
    plugin = Tokra::Image::Plugin.new(nil, {})
    webview = build_webview

    non_image = Object.new.extend(Tokra::Resource)
    rid = webview.resources_table.add(non_image)

    rejected_message = nil
    invoke = Tokra::Ipc::Invoke.new(
      command: "size",
      payload: { "rid" => rid },
      webview:,
      responder: -> (success, value) { rejected_message = JSON.parse(value) unless success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    assert_equal "The resource id #{rid} is invalid.", rejected_message,
      "non-Image resource should reject like Tauri's typed downcast"
  end

  def test_new_rejects_non_array_rgba
    assert_rejects_invalid_args("new",
      { "rgba" => "not-an-array", "width" => 1, "height" => 1 },
      "invalid args `rgba` for command `new`: invalid type: string \"not-an-array\", expected a sequence")
  end

  def test_new_rejects_non_integer_width
    assert_rejects_invalid_args("new",
      { "rgba" => [0, 0, 0, 0], "width" => "1", "height" => 1 },
      "invalid args `width` for command `new`: invalid type: string \"1\", expected u32")
  end

  def test_new_rejects_non_integer_height
    assert_rejects_invalid_args("new",
      { "rgba" => [0, 0, 0, 0], "width" => 1, "height" => nil },
      "invalid args `height` for command `new`: invalid type: null, expected u32")
  end

  def test_from_bytes_decodes_and_stores_image
    plugin = Tokra::Image::Plugin.new(nil, {})
    webview = build_webview
    png_bytes = File.binread(fixture_path("2x2.png")).bytes

    resolved_rid = nil
    invoke = Tokra::Ipc::Invoke.new(
      command: "from_bytes",
      payload: { "bytes" => png_bytes },
      webview:,
      responder: -> (success, value) { resolved_rid = JSON.parse(value) if success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    image = webview.resources_table.get(resolved_rid)
    assert_instance_of Tokra::Image, image, "decoded resource should be an Image"
    assert_equal 2, image.width, "should decode the PNG dimensions"
  end

  def test_from_bytes_rejects_undecodable_bytes
    plugin = Tokra::Image::Plugin.new(nil, {})

    rejected_message = nil
    invoke = Tokra::Ipc::Invoke.new(
      command: "from_bytes",
      payload: { "bytes" => [1, 2, 3] },
      webview: build_webview,
      responder: -> (success, value) { rejected_message = JSON.parse(value) unless success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    assert_match(/\Afailed to process image/, rejected_message,
      "should reject with Tauri's failed-to-process-image message")
  end

  def test_from_path_decodes_and_stores_image
    plugin = Tokra::Image::Plugin.new(nil, {})
    webview = build_webview

    resolved_rid = nil
    invoke = Tokra::Ipc::Invoke.new(
      command: "from_path",
      payload: { "path" => fixture_path("2x2.ico") },
      webview:,
      responder: -> (success, value) { resolved_rid = JSON.parse(value) if success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    assert_equal 2, webview.resources_table.get(resolved_rid).height,
      "should decode the ICO file at path"
  end

  def test_from_path_rejects_missing_file
    plugin = Tokra::Image::Plugin.new(nil, {})

    rejected = false
    invoke = Tokra::Ipc::Invoke.new(
      command: "from_path",
      payload: { "path" => fixture_path("missing.png") },
      webview: build_webview,
      responder: -> (success, _value) { rejected = !success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    assert rejected, "unreadable path should reject the invoke"
  end

  def test_from_path_rejects_a_path_with_a_nul_byte_as_tauri_does
    expected = Gem.win_platform? ? "strings passed to WinAPI cannot contain NULs" : "file name contained an unexpected NUL byte"
    assert_rejects_invalid_args("from_path", { "path" => "a\0b.png" }, expected)
  end

  def test_from_path_rejects_non_string_path
    assert_rejects_invalid_args("from_path",
      { "path" => 42 },
      "invalid args `path` for command `from_path`: invalid type: integer `42`, expected path string")
  end

  # Each argument reads as its Rust type does (image/plugin.rs): rgba and
  # bytes as Vec<u8>, width, height, and rid as u32, and path as a
  # PathBuf. The messages are what the locked serde 1.0.228 and
  # serde_json 1.0.145 give through Tauri's CommandItem.
  INVALID_ARGS = {
    ["new", { "width" => 1, "height" => 1 }] =>
      "invalid args `rgba` for command `new`: command new missing required key rgba",
    ["new", { "rgba" => [256, 0, 0, 0], "width" => 1, "height" => 1 }] =>
      "invalid args `rgba` for command `new`: invalid value: integer `256`, expected u8",
    ["new", { "rgba" => [-1], "width" => 1, "height" => 1 }] =>
      "invalid args `rgba` for command `new`: invalid value: integer `-1`, expected u8",
    ["new", { "rgba" => [1.5], "width" => 1, "height" => 1 }] =>
      "invalid args `rgba` for command `new`: invalid type: floating point `1.5`, expected u8",
    ["new", { "rgba" => ["a"], "width" => 1, "height" => 1 }] =>
      "invalid args `rgba` for command `new`: invalid type: string \"a\", expected u8",
    ["new", { "rgba" => [0, 0, 0, 0], "width" => -1, "height" => 1 }] =>
      "invalid args `width` for command `new`: invalid value: integer `-1`, expected u32",
    ["new", { "rgba" => [0, 0, 0, 0], "width" => 2 ** 32, "height" => 1 }] =>
      "invalid args `width` for command `new`: invalid value: integer `4294967296`, expected u32",
    ["new", { "rgba" => [0, 0, 0, 0], "width" => 2 ** 64, "height" => 1 }] =>
      "invalid args `width` for command `new`: invalid type: floating point `1.8446744073709552e19`, expected u32",
    ["new", { "rgba" => [0, 0, 0, 0], "width" => 1.0, "height" => 1 }] =>
      "invalid args `width` for command `new`: invalid type: floating point `1.0`, expected u32",
    ["new", { "rgba" => "x", "width" => "y", "height" => 1 }] =>
      "invalid args `rgba` for command `new`: invalid type: string \"x\", expected a sequence",
    ["from_bytes", { "bytes" => "x" }] =>
      "invalid args `bytes` for command `from_bytes`: invalid type: string \"x\", expected a sequence",
    ["from_bytes", { "bytes" => {} }] =>
      "invalid args `bytes` for command `from_bytes`: invalid type: map, expected a sequence",
    ["from_bytes", {}] =>
      "invalid args `bytes` for command `from_bytes`: command from_bytes missing required key bytes",
    ["from_path", { "path" => ["a"] }] =>
      "invalid args `path` for command `from_path`: invalid type: sequence, expected path string",
    ["from_path", {}] =>
      "invalid args `path` for command `from_path`: command from_path missing required key path",
    ["rgba", { "rid" => "x" }] =>
      "invalid args `rid` for command `rgba`: invalid type: string \"x\", expected u32",
    ["rgba", {}] =>
      "invalid args `rid` for command `rgba`: command rgba missing required key rid",
    ["size", { "rid" => 2 ** 32 }] =>
      "invalid args `rid` for command `size`: invalid value: integer `4294967296`, expected u32",
    ["size", { "rid" => -1 }] =>
      "invalid args `rid` for command `size`: invalid value: integer `-1`, expected u32",
    ["size", { "rid" => nil }] =>
      "invalid args `rid` for command `size`: invalid type: null, expected u32",
  }.freeze

  def test_bad_arguments_reject_with_tauris_messages
    INVALID_ARGS.each do |(command, payload), message|
      assert_rejects_invalid_args(command, payload, message)
    end
  end

  def test_the_largest_u32_is_a_valid_dimension
    webview = build_webview
    resolved = nil
    invoke = Tokra::Ipc::Invoke.new(
      command: "new",
      payload: { "rgba" => [], "width" => (2 ** 32) - 1, "height" => 0 },
      webview:,
      responder: -> (success, value) { resolved = JSON.parse(value) if success }
    )

    assert Tokra::Image::Plugin.new(nil, {}).extend_api(invoke)
    assert_equal (2 ** 32) - 1, webview.resources_table.get(resolved).width
  end

  def test_an_argument_error_from_a_bug_is_not_taken_for_a_bad_argument
    webview = build_webview
    webview.resources_table.define_singleton_method(:add) { |_resource| raise ArgumentError, "a bug" }
    invoke = Tokra::Ipc::Invoke.new(
      command: "new",
      payload: { "rgba" => [0, 0, 0, 0], "width" => 1, "height" => 1 },
      webview:,
      responder: -> (_success, _value) {}
    )

    error = assert_raises(ArgumentError) { Tokra::Image::Plugin.new(nil, {}).extend_api(invoke) }
    assert_equal "a bug", error.message
  end

  private def build_webview
    Struct.new(:resources_table).new(Tokra::ResourceTable.new)
  end

  # Returns the absolute path of a fixture file.
  private def fixture_path(name)
    File.expand_path("../fixtures/#{name}", __dir__)
  end

  # Asserts that the command rejects the payload with the given message.
  private def assert_rejects_invalid_args(command, payload, expected_message)
    plugin = Tokra::Image::Plugin.new(nil, {})
    rejected_message = nil
    invoke = Tokra::Ipc::Invoke.new(
      command:,
      payload:,
      webview: build_webview,
      responder: -> (success, value) { rejected_message = JSON.parse(value) unless success }
    )

    result = plugin.extend_api(invoke)

    assert result, "extend_api should return true (command was handled)"
    assert_equal expected_message, rejected_message
  end
end
