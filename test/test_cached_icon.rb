# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/config_fixtures"

# Tokra::Codegen::CachedIcon, tauri-codegen's CachedIcon (image.rs:22-118),
# held up against what codegen itself made of each file under
# test/fixtures/config/icons: the bytes it cached and the size it wrote, or
# the error it returned, or the message it panicked with (plan 054,
# phase 3). rake config:fixtures writes the answers.
class TestCachedIcon < Minitest::Test
  CachedIcon = Tokra::Codegen::CachedIcon
  DIR = File.join(ConfigFixtures::ROOT, "icons")

  # Every answer codegen gave, one test each, so a mismatch names its file.
  ANSWERS = File.readlines(File.join(DIR, "expected.jsonl"), chomp: true).reject(&:empty?)
    .map { |line| Tokra::Ipc::Json.parse(line) }

  ANSWERS.each do |answer|
    name = answer.fetch("name")
    call = answer.fetch("call")
    define_method("test_#{call}_#{name.tr('.', '_')}_as_codegen_reads_it") { assert_codegen_answer(answer) }
  end

  def test_every_icon_has_an_answer
    named = ANSWERS.map { |answer| answer.fetch("name") }.uniq
    assert_equal (Dir.children(DIR) - ["expected.jsonl"] + %w[missing.png missing.icns]).sort, named.sort
  end

  # The measured answer to plan 054's open question: codegen's
  # `while let Ok(Some(row))` keeps an interlaced PNG's Adam7 passes in
  # the order png 0.17.16 yields them, so the pixels are all there but
  # out of place; pixel (4, 0) follows pixel (0, 0).
  def test_an_interlaced_png_keeps_its_adam7_passes_in_order
    image = CachedIcon.new(File.join(DIR, "rgba_interlaced.png")).value
    assert_equal [5, 5, 100], [image.width, image.height, image.rgba.bytesize]
    pixels = image.rgba.unpack("a4" * 25)
    assert_equal pixel(4, 0, 5), pixels[1]
    refute_equal pixel(1, 0, 5), pixels[1]
  end

  # ... and a PNG whose data stops early keeps the rows read before the
  # error, with the header's size: two of four rows here.
  def test_a_truncated_png_keeps_the_rows_read_before_the_error
    image = CachedIcon.new(File.join(DIR, "rgba_truncated.png")).value
    assert_equal [4, 4], [image.width, image.height]
    assert_equal (0...8).map { |i| pixel(i % 4, i / 4, 4) }.join, image.rgba
  end

  # A PNG of 16 bits a channel is RGBA, so codegen keeps its eight bytes a
  # pixel, more than an Image of its size holds.
  def test_a_sixteen_bit_png_keeps_eight_bytes_a_pixel
    image = CachedIcon.new(File.join(DIR, "rgba16.png")).value
    assert_equal 2 * 2 * 8, image.rgba.bytesize
  end

  def test_an_ico_answers_its_first_entry_not_its_largest
    image = CachedIcon.new(File.join(DIR, "icon.ico")).value
    assert_equal [3, 2], [image.width, image.height]
  end

  def test_the_cache_is_frozen_binary
    icon = CachedIcon.new_raw(File.join(DIR, "icon.icns"))
    assert icon.cache.frozen?
    assert_equal Encoding::BINARY, icon.cache.encoding
    assert_same icon.cache, icon.value
  end

  # Rust's Path::extension: no extension for a dotfile or a name without a
  # dot, so these are invalid with an empty one.
  def test_a_name_without_an_extension_is_invalid_with_an_empty_one
    %w[icon .png].each do |name|
      error = assert_raises(Tokra::Codegen::EmbeddedAssetsError::InvalidImageExtension) do
        CachedIcon.new(File.join(DIR, name))
      end
      assert_equal "", error.extension
      assert_equal "invalid extension `` used for image #{File.join(DIR, name)}, must be `ico` or `png`", error.message
    end
  end

  def test_the_extension_is_matched_case_sensitively
    error = assert_raises(Tokra::Codegen::EmbeddedAssetsError::InvalidImageExtension) do
      CachedIcon.new(File.join(DIR, "icon.PNG"))
    end
    assert_equal "PNG", error.extension
    assert_equal File.join(DIR, "icon.PNG"), error.path
  end

  def test_a_directory_fails_to_open_in_rusts_words
    error = assert_raises(RuntimeError) { CachedIcon.new_raw(DIR) }
    assert_match(/\Afailed to open icon #{Regexp.escape(DIR)}: .+ \(os error \d+\)\z/, error.message)
  end

  # Each path as Rust displays it, as Codegen's find_icon builds one, so a
  # message names it in Tauri's words on Windows too.
  private def assert_codegen_answer(answer)
    path = Tokra::Utils::Config::Parse.display(File.join(DIR, answer.fetch("name")))
    call = answer.fetch("call")
    label = "#{call} #{answer.fetch('name')}"
    if answer.key?("ok")
      assert_ok(answer.fetch("ok"), CachedIcon.public_send(call, path).value, label)
    elsif answer.key?("panic")
      error = assert_raises(RuntimeError, label) { CachedIcon.public_send(call, path) }
      assert_instance_of RuntimeError, error, label
      assert_equal std_text(ConfigFixtures.fill(answer.fetch("panic"), DIR), path), error.message, label
    else
      error = assert_raises(Tokra::Codegen::EmbeddedAssetsError::InvalidImageExtension, label) do
        CachedIcon.public_send(call, path)
      end
      assert_equal ConfigFixtures.fill(answer.fetch("error"), DIR), error.message, label
    end
  end

  private def assert_ok(ok, value, label)
    if ok.key?("width")
      assert_instance_of Tokra::Image, value, label
      assert_equal [ok.fetch("width"), ok.fetch("height")], [value.width, value.height], label
      assert_equal ok.fetch("bytes"), value.rgba.unpack1("H*"), label
    else
      assert_equal ok.fetch("bytes"), value.unpack1("H*"), label
    end
  end

  # +message+ with the generator's macOS text for a missing file as std
  # words it on this platform, such as Windows's "The system cannot find
  # the file specified. (os error 2)".
  private def std_text(message, path)
    unix = "No such file or directory (os error 2)"
    return message unless message.end_with?(unix)

    Tokra::Native.fs_read(path)
    flunk "#{path} exists"
  rescue RuntimeError => e
    message.delete_suffix(unix) + e.message
  end

  # The pixel test/fixtures/config/icons gives (x, y) of a +w+-wide image.
  private def pixel(x, y, w)
    i = (y * w) + x
    [i * 9 % 256, ((i * 37) + 11) % 256, ((i * 71) + 23) % 256, 255 - i].pack("C4")
  end
end
