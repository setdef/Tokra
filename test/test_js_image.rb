# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::JsImage.
#
# JsImage reads the four frontend image payload shapes as Tauri's
# JsImage deserializes them, and resolves them into Tokra::Image as its
# into_img does (image/mod.rs:158-230).
class TestJsImage < Minitest::Test
  RGBA_2X2 = "\xFF\x00\x00\xFF\x00\xFF\x00\xFF\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF".b

  # Resource that is not an Image, for typed-downcast coverage.
  class NotAnImage
    include Tokra::Resource
  end

  def test_integer_resolves_stored_image
    table = Tokra::ResourceTable.new
    image = Tokra::Image.new(rgba: RGBA_2X2, width: 2, height: 2)
    rid = table.add(image)

    assert_same image, Tokra::JsImage.deserialize(rid).into_img(table)
  end

  def test_integer_with_non_image_resource_raises_bad_resource_id
    table = Tokra::ResourceTable.new
    rid = table.add(NotAnImage.new)

    error = assert_raises(Tokra::Error::BadResourceId) do
      Tokra::JsImage.deserialize(rid).into_img(table)
    end
    assert_equal rid, error.rid
  end

  def test_unknown_rid_raises_bad_resource_id
    error = assert_raises(Tokra::Error::BadResourceId) do
      Tokra::JsImage.deserialize(999).into_img(Tokra::ResourceTable.new)
    end
    assert_equal 999, error.rid
  end

  def test_array_decodes_encoded_bytes
    bytes = File.binread(fixture_path("2x2.png")).bytes
    image = Tokra::JsImage.deserialize(bytes).into_img(Tokra::ResourceTable.new)

    assert_equal 2, image.width
    assert_equal 2, image.height
    assert_equal RGBA_2X2, image.rgba
  end

  def test_array_with_non_integers_is_a_mismatch
    error = assert_raises(Tokra::Ipc::CommandItem::Mismatch) do
      Tokra::JsImage.deserialize(["not", "bytes"])
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  def test_array_with_undecodable_bytes_raises_error_image
    assert_raises(Tokra::Error::Image) do
      Tokra::JsImage.deserialize([0, 1, 2, 3]).into_img(Tokra::ResourceTable.new)
    end
  end

  def test_string_decodes_file_at_path
    image = Tokra::JsImage.deserialize(fixture_path("2x2.ico")).into_img(Tokra::ResourceTable.new)

    assert_equal RGBA_2X2, image.rgba
  end

  def test_hash_builds_inline_rgba_image
    payload = { "rgba" => RGBA_2X2.bytes, "width" => 2, "height" => 2 }
    image = Tokra::JsImage.deserialize(payload).into_img(Tokra::ResourceTable.new)

    assert_equal 2, image.width
    assert_equal 2, image.height
    assert_equal RGBA_2X2, image.rgba
  end

  def test_hash_with_missing_keys_is_a_mismatch
    error = assert_raises(Tokra::Ipc::CommandItem::Mismatch) do
      Tokra::JsImage.deserialize({ "rgba" => [0, 0, 0, 0] })
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  def test_unsupported_value_is_a_mismatch
    error = assert_raises(Tokra::Ipc::CommandItem::Mismatch) do
      Tokra::JsImage.deserialize(nil)
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  # serde's message for Tauri's untagged JsImage enum, verbatim.
  def test_mismatch_message_is_serdes_untagged_enum_error
    assert_equal "data did not match any variant of untagged enum JsImage", Tokra::JsImage::MISMATCH
  end

  # Vec<u8> rejects 256 and -1 rather than wrapping them, and 1.5 rather
  # than truncating it, so pack("C*") never sees them.
  def test_bytes_outside_u8_are_rejected_not_wrapped
    [[256], [-1], [1.5]].each do |bytes|
      error = assert_raises(Tokra::Ipc::CommandItem::Mismatch, "#{bytes.inspect} is not a u8 array") do
        Tokra::JsImage.deserialize({ "rgba" => bytes, "width" => 1, "height" => 1 })
      end
      assert_equal Tokra::JsImage::MISMATCH, error.message
    end
  end

  def test_u8_bounds_are_accepted
    image = Tokra::JsImage.deserialize({ "rgba" => [0, 255, 0, 255], "width" => 1, "height" => 1 })
      .into_img(Tokra::ResourceTable.new)
    assert_equal "\x00\xFF\x00\xFF".b, image.rgba
  end

  def test_dimensions_outside_u32_are_rejected
    [-1, 2 ** 32, 1.0, "1", nil].each do |dimension|
      [["width", dimension, "height", 1], ["height", dimension, "width", 1]].each do |key, value, other, other_value|
        assert_raises(Tokra::Ipc::CommandItem::Mismatch, "#{key} #{dimension.inspect} is not a u32") do
          Tokra::JsImage.deserialize({ "rgba" => [], key => value, other => other_value })
        end
      end
    end
  end

  def test_u32_max_dimension_is_accepted
    image = Tokra::JsImage.deserialize({ "rgba" => [], "width" => (2 ** 32) - 1, "height" => 0 })
      .into_img(Tokra::ResourceTable.new)
    assert_equal (2 ** 32) - 1, image.width, "u32::MAX is a valid width"
    assert_equal 0, image.height
  end

  def test_resource_ids_outside_u32_are_rejected
    [-1, 2 ** 32].each do |rid|
      error = assert_raises(Tokra::Ipc::CommandItem::Mismatch) { Tokra::JsImage.deserialize(rid) }
      assert_equal Tokra::JsImage::MISMATCH, error.message
    end
  end

  def test_hash_without_rgba_array_is_rejected
    error = assert_raises(Tokra::Ipc::CommandItem::Mismatch) do
      Tokra::JsImage.deserialize({ "rgba" => "AAAA", "width" => 1, "height" => 1 })
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  # serde_derive gives an untagged enum's struct variant no visit_seq
  # (serde_derive 1.0.228 de/struct_.rs:70-73), so Tauri does not read
  # [rgba, width, height] as the Rgba variant, though it reads a plain
  # struct that way. The locked serde rejects each of these.
  def test_a_sequence_is_not_the_rgba_variant
    [[RGBA_2X2.bytes, 2, 2], [[], 1, 1], [[0, 0, 0, 0], -1, 1], [[0, 0, 0, 0], 1, 1, 1]].each do |sequence|
      error = assert_raises(Tokra::Ipc::CommandItem::Mismatch, sequence.inspect) do
        Tokra::JsImage.deserialize(sequence)
      end
      assert_equal Tokra::JsImage::MISMATCH, error.message
    end
  end

  # Tauri deserializes the argument before the command runs and resolves
  # it inside the command, so a well-formed payload that names nothing
  # deserializes, and only into_img fails.
  def test_resolution_failures_come_from_into_img_not_deserialize
    table = Tokra::ResourceTable.new
    unknown = Tokra::JsImage.deserialize(999)
    undecodable = Tokra::JsImage.deserialize([0, 1, 2, 3])
    missing = Tokra::JsImage.deserialize(fixture_path("missing.png"))

    assert_raises(Tokra::Error::BadResourceId) { unknown.into_img(table) }
    assert_raises(Tokra::Error::Image) { undecodable.into_img(table) }
    assert_raises(Tokra::Error::Io) { missing.into_img(table) }
  end

  # serde reads any string as a PathBuf, NUL bytes and all; only reading
  # the file fails, with Error::Io.
  def test_a_path_with_a_nul_byte_deserializes_and_fails_to_resolve
    js_image = Tokra::JsImage.deserialize("a\0b.png")

    assert_raises(Tokra::Error::Io) { js_image.into_img(Tokra::ResourceTable.new) }
  end

  # A JsImage exists only as deserialize reads it, as Tauri's
  # non-exhaustive variants cannot be built outside the crate.
  def test_new_is_private
    assert_raises(NoMethodError) { Tokra::JsImage.new(1) }
  end

  # A mismatch is serde's error for the argument, not an ArgumentError, so
  # a plugin can rescue exactly it.
  def test_a_mismatch_is_not_an_argument_error
    refute_operator Tokra::Ipc::CommandItem::Mismatch, :<=, ArgumentError
  end

  private def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end
end
