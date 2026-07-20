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
    assert_equal "invalid args: image bytes must be integers", error.message
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
    assert_equal "invalid args: image hash must have an rgba array, an integer width, and an integer height",
      error.message
  end

  def test_unsupported_value_raises_argument_error
    error = assert_raises(ArgumentError) do
      Tokra::JsImage.new(nil).into_img(Tokra::ResourceTable.new)
    end
    assert_equal "invalid args: image must be a resource ID, byte array, file path, or RGBA hash",
      error.message
  end

  private def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end
end
