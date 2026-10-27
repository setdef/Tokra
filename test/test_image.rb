# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Image.
class TestImage < Minitest::Test
  def test_from_bytes_decodes_png
    image = Tokra::Image.from_bytes(File.binread(fixture_path("2x2.png")))

    assert_equal 2, image.width, "should decode PNG width"
    assert_equal 2, image.height, "should decode PNG height"
    assert_equal File.binread(fixture_path("2x2_rgba.bin")), image.rgba,
      "decoded RGBA should match the known raw pixels"
  end

  def test_from_bytes_decodes_ico
    image = Tokra::Image.from_bytes(File.binread(fixture_path("2x2.ico")))

    assert_equal 2, image.width, "should decode ICO width"
    assert_equal File.binread(fixture_path("2x2_rgba.bin")), image.rgba,
      "decoded RGBA should match the known raw pixels"
  end

  def test_from_bytes_raises_error_image_for_undecodable_bytes
    error = assert_raises(Tokra::Error::Image) { Tokra::Image.from_bytes("garbage") }
    assert_match(/\Afailed to process image/, error.message,
      "message should keep Tauri's failed-to-process-image prefix")
  end

  def test_from_path_decodes_file
    image = Tokra::Image.from_path(fixture_path("2x2.png"))

    assert_equal 2, image.height, "should decode the file at path"
  end

  # Tauri's from_path returns Error::Io, whose message is the io::Error's.
  def test_from_path_raises_error_io_for_missing_file
    path = fixture_path("missing.png")
    error = assert_raises(Tokra::Error::Io) { Tokra::Image.from_path(path) }

    assert_equal "No such file or directory @ rb_sysopen - #{path}", error.message
  end

  # Rust cannot hand a path with a NUL byte to the OS, so std::fs::read
  # fails with an io::Error where Ruby's File.binread raises ArgumentError
  # (std sys/helpers/small_c_string.rs:13-14; on Windows,
  # sys/pal/windows/mod.rs:99-104).
  def test_from_path_raises_error_io_for_a_nul_byte
    error = assert_raises(Tokra::Error::Io) { Tokra::Image.from_path("a\0b.png") }

    expected = Gem.win_platform? ? "strings passed to WinAPI cannot contain NULs" : "file name contained an unexpected NUL byte"
    assert_equal expected, error.message
  end

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

  # Returns the absolute path of a fixture file.
  private def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end
end
