# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Image.
class TestImage < Minitest::Test
  def test_stores_rgba_data
    rgba = "\xFF\x00\x00\xFF".b # 1x1 red pixel
    image = Tokra::Image.new(rgba:, width: 1, height: 1)

    assert_equal rgba, image.rgba, "should store rgba data"
    assert_equal 1, image.width, "should store width"
    assert_equal 1, image.height, "should store height"
  end

  def test_positional_constructor
    rgba = "\xFF\x00\x00\xFF".b
    image = Tokra::Image.new(rgba, 1, 1)

    assert_equal rgba, image.rgba, "positional args should work"
  end

  def test_name_returns_identifier
    image = Tokra::Image.new(rgba: "", width: 0, height: 0)
    assert_equal "Tokra::Image", image.name
  end

  def test_close_returns_nil
    image = Tokra::Image.new(rgba: "", width: 0, height: 0)
    assert_nil image.close
  end

  def test_includes_resource_module
    assert_includes Tokra::Image.ancestors, Tokra::Resource
  end

  def test_integration_with_resource_table
    table = Tokra::ResourceTable.new
    rgba = "\xFF\x00\x00\xFF\x00\xFF\x00\xFF".b # 2x1 image
    image = Tokra::Image.new(rgba:, width: 2, height: 1)

    rid = table.add(image)
    retrieved = table.get(rid)

    assert_same image, retrieved, "ResourceTable should store and retrieve Image"
    assert_equal 2, retrieved.width
  end

  def test_round_trip_file_io
    require "digest"
    require "tempfile"

    # Load from fixture file on disk
    fixture_path = File.expand_path("fixtures/2x2_rgba.bin", __dir__)
    loaded_rgba = File.binread(fixture_path)
    image = Tokra::Image.new(rgba: loaded_rgba, width: 2, height: 2)

    # Store in ResourceTable
    table = Tokra::ResourceTable.new
    rid = table.add(image)

    # Retrieve from ResourceTable
    retrieved = table.get(rid)

    # Write to new temp file
    output_file = Tempfile.new(["output", ".rgba"])
    begin
      output_file.binmode
      output_file.write(retrieved.rgba)
      output_file.close

      # Compare hashes
      original_hash = Digest::SHA256.file(fixture_path)
      output_hash = Digest::SHA256.file(output_file.path)

      assert_equal original_hash.hexdigest, output_hash.hexdigest,
        "Retrieved image data should match original file exactly"
    ensure
      output_file.close!
    end
  end
end
