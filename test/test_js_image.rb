# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::JsImage.
#
# JsImage resolves the four frontend image payload shapes into
# Tokra::Image, matching Tauri's JsImage#into_img (image/mod.rs).
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

    assert_same image, Tokra::JsImage.new(rid).into_img(table)
  end

  def test_integer_with_non_image_resource_raises_bad_resource_id
    table = Tokra::ResourceTable.new
    rid = table.add(NotAnImage.new)

    error = assert_raises(Tokra::Error::BadResourceId) do
      Tokra::JsImage.new(rid).into_img(table)
    end
    assert_equal rid, error.rid
  end

  def test_unknown_rid_raises_bad_resource_id
    error = assert_raises(Tokra::Error::BadResourceId) do
      Tokra::JsImage.new(999).into_img(Tokra::ResourceTable.new)
    end
    assert_equal 999, error.rid
  end

  def test_array_decodes_encoded_bytes
    bytes = File.binread(fixture_path("2x2.png")).bytes
    image = Tokra::JsImage.new(bytes).into_img(Tokra::ResourceTable.new)

    assert_equal 2, image.width
    assert_equal 2, image.height
    assert_equal RGBA_2X2, image.rgba
  end

  def test_array_with_non_integers_raises_argument_error
    error = assert_raises(ArgumentError) do
      Tokra::JsImage.new(["not", "bytes"]).into_img(Tokra::ResourceTable.new)
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  def test_array_with_undecodable_bytes_raises_error_image
    assert_raises(Tokra::Error::Image) do
      Tokra::JsImage.new([0, 1, 2, 3]).into_img(Tokra::ResourceTable.new)
    end
  end

  def test_string_decodes_file_at_path
    image = Tokra::JsImage.new(fixture_path("2x2.ico")).into_img(Tokra::ResourceTable.new)

    assert_equal RGBA_2X2, image.rgba
  end

  def test_hash_builds_inline_rgba_image
    payload = { "rgba" => RGBA_2X2.bytes, "width" => 2, "height" => 2 }
    image = Tokra::JsImage.new(payload).into_img(Tokra::ResourceTable.new)

    assert_equal 2, image.width
    assert_equal 2, image.height
    assert_equal RGBA_2X2, image.rgba
  end

  def test_hash_with_missing_keys_raises_argument_error
    error = assert_raises(ArgumentError) do
      Tokra::JsImage.new({ "rgba" => [0, 0, 0, 0] }).into_img(Tokra::ResourceTable.new)
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  def test_unsupported_value_raises_argument_error
    error = assert_raises(ArgumentError) do
      Tokra::JsImage.new(nil).into_img(Tokra::ResourceTable.new)
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
      error = assert_raises(ArgumentError, "#{bytes.inspect} is not a u8 array") do
        Tokra::JsImage.new({ "rgba" => bytes, "width" => 1, "height" => 1 }).into_img(Tokra::ResourceTable.new)
      end
      assert_equal Tokra::JsImage::MISMATCH, error.message
    end
  end

  def test_u8_bounds_are_accepted
    image = Tokra::JsImage.new({ "rgba" => [0, 255, 0, 255], "width" => 1, "height" => 1 })
      .into_img(Tokra::ResourceTable.new)
    assert_equal "\x00\xFF\x00\xFF".b, image.rgba
  end

  def test_dimensions_outside_u32_are_rejected
    [-1, 2 ** 32, 1.0, "1", nil].each do |dimension|
      [["width", dimension, "height", 1], ["height", dimension, "width", 1]].each do |key, value, other, other_value|
        assert_raises(ArgumentError, "#{key} #{dimension.inspect} is not a u32") do
          Tokra::JsImage.new({ "rgba" => [], key => value, other => other_value }).into_img(Tokra::ResourceTable.new)
        end
      end
    end
  end

  def test_u32_max_dimension_is_accepted
    image = Tokra::JsImage.new({ "rgba" => [], "width" => (2 ** 32) - 1, "height" => 0 })
      .into_img(Tokra::ResourceTable.new)
    assert_equal (2 ** 32) - 1, image.width, "u32::MAX is a valid width"
    assert_equal 0, image.height
  end

  def test_resource_ids_outside_u32_are_rejected
    table = Tokra::ResourceTable.new
    [-1, 2 ** 32].each do |rid|
      error = assert_raises(ArgumentError) { Tokra::JsImage.new(rid).into_img(table) }
      assert_equal Tokra::JsImage::MISMATCH, error.message
    end
  end

  def test_hash_without_rgba_array_is_rejected
    error = assert_raises(ArgumentError) do
      Tokra::JsImage.new({ "rgba" => "AAAA", "width" => 1, "height" => 1 }).into_img(Tokra::ResourceTable.new)
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  # serde's derived struct visitor accepts a sequence in field order, so
  # Tauri reads [rgba, width, height] as the Rgba variant.
  def test_three_element_sequence_is_the_rgba_variant
    image = Tokra::JsImage.new([RGBA_2X2.bytes, 2, 2]).into_img(Tokra::ResourceTable.new)

    assert_equal Tokra::Image.new(rgba: RGBA_2X2, width: 2, height: 2), image
  end

  def test_sequence_form_validates_like_the_hash_form
    error = assert_raises(ArgumentError) do
      Tokra::JsImage.new([[0, 0, 0, 0], -1, 1]).into_img(Tokra::ResourceTable.new)
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message
  end

  def test_sequence_of_the_wrong_length_is_not_the_rgba_variant
    error = assert_raises(ArgumentError) do
      Tokra::JsImage.new([[0, 0, 0, 0], 1, 1, 1]).into_img(Tokra::ResourceTable.new)
    end
    assert_equal Tokra::JsImage::MISMATCH, error.message, "serde rejects trailing elements"
  end

  private def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end
end
