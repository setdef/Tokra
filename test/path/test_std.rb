# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "rust_path_cases"

# Tokra::Path::Std answers as Rust's std::path does on each platform,
# checked against Rust's own tests (std tests/path.rs), so the path API
# joins and splits paths as Tauri's does wherever the tests run.
class TestPathStd < Minitest::Test
  Std = Tokra::Path::Std

  def test_unix_decomposes_as_rust_does
    assert_decompositions Std::UNIX, RustPathCases::UNIX_DECOMPOSITIONS
  end

  def test_windows_decomposes_as_rust_does
    assert_decompositions Std::WINDOWS, RustPathCases::WINDOWS_DECOMPOSITIONS
  end

  def test_unix_pushes_as_rust_does
    RustPathCases::UNIX_PUSHES.each do |path, pushed, expected|
      assert_equal expected, Std::UNIX.push(path, pushed), "pushing #{pushed.inspect} onto #{path.inspect}"
    end
  end

  def test_windows_pushes_as_rust_does
    RustPathCases::WINDOWS_PUSHES.each do |path, pushed, expected|
      assert_equal expected, Std::WINDOWS.push(path, pushed), "pushing #{pushed.inspect} onto #{path.inspect}"
    end
  end

  def test_pop_keeps_the_parent_as_rust_does
    [
      [Std::UNIX, RustPathCases::COMMON_POPS],
      [Std::WINDOWS, RustPathCases::COMMON_POPS + RustPathCases::WINDOWS_POPS],
].each do |std, cases|
      cases.each do |path, expected, popped|
        parent = std.parent(path)

        assert_equal popped, !parent.nil?, "popping #{path.inspect}"
        assert_equal expected, parent || path, "popping #{path.inspect}"
      end
    end
  end

  # A backslash separates only on Windows, so on Unix it stays in the
  # file name and its extension.
  def test_a_backslash_is_part_of_a_unix_file_name
    assert_equal "txt\\", Std::UNIX.extension("foo.txt\\")
    assert_equal "txt", Std::WINDOWS.extension("foo.txt\\")
    assert_equal "a\\b", Std::UNIX.file_name("a\\b")
    assert_equal "b", Std::WINDOWS.file_name("a\\b")
  end

  def test_each_platform_has_its_separator
    assert_equal "/", Std::UNIX.separator
    assert_equal "\\", Std::WINDOWS.separator
  end

  def test_the_std_for_a_target
    assert_same Std::UNIX, Std.for(Tokra::Utils::Platform::Target::MacOS)
    assert_same Std::UNIX, Std.for(Tokra::Utils::Platform::Target::Linux)
    assert_same Std::WINDOWS, Std.for(Tokra::Utils::Platform::Target::Windows)
  end

  # dunce 1.0.5's simplified: a verbatim disk path whose every part a
  # legacy program could open loses its \\?\, and anything else stays.
  def test_dunce_simplifies_a_verbatim_disk_path_on_windows
    {
      "\\\\?\\C:\\Windows" => "C:\\Windows",
      "\\\\?\\C:\\" => "C:\\",
      "\\\\?\\C:" => "C:",
      "\\\\?\\c:\\foo\\bar" => "c:\\foo\\bar",
      "C:\\foo" => "C:\\foo",
      "\\\\?\\UNC\\server\\share\\x" => "\\\\?\\UNC\\server\\share\\x",
      "\\\\?\\C:\\foo\\..\\bar" => "\\\\?\\C:\\foo\\..\\bar",
      "\\\\?\\C:\\foo\\." => "\\\\?\\C:\\foo\\.",
      "\\\\?\\C:\\con" => "\\\\?\\C:\\con",
      "\\\\?\\C:\\Com1.txt" => "\\\\?\\C:\\Com1.txt",
      "\\\\?\\C:\\con.. .txt" => "\\\\?\\C:\\con.. .txt",
      "\\\\?\\C:\\console" => "C:\\console",
      "\\\\?\\C:\\a:b" => "\\\\?\\C:\\a:b",
      "\\\\?\\C:\\trailing." => "\\\\?\\C:\\trailing.",
      "\\\\?\\C:\\trailing " => "\\\\?\\C:\\trailing ",
      "\\\\?\\C:\\#{'a' * 256}" => "\\\\?\\C:\\#{'a' * 256}",
      "\\\\?\\C:\\#{'a' * 253}" => "C:\\#{'a' * 253}",
      "\\\\?\\C:\\#{'a\\' * 127}" => "\\\\?\\C:\\#{'a\\' * 127}",
      "\\\\?\\C:\\#{'a\\' * 126}" => "C:\\#{'a\\' * 126}",
    }.each do |path, expected|
      assert_equal expected, Std::WINDOWS.simplified(path), path
    end
  end

  # dunce's own is_reserved and is_valid_filename cases (lib.rs tests),
  # as a file name after \\?\C:\, which keeps its prefix when the name
  # is reserved or invalid.
  def test_dunce_keeps_the_prefix_for_a_reserved_or_invalid_name
    reserved_or_invalid = [
      "CON",
      "con",
      "con.con",
      "COM4",
      "COM4.txt",
      "COM4 .txt",
      "con.",
      "con .",
      "con  ",
      "con . ",
      "con . .txt",
      "con.....txt",
      "PrN.....",
      " PrN.....",
      "aaaaaaaaaa:",
      "ą:ą",
      "a ",
      " a. ",
      "<x>",
      "a*",
      "?x",
      "a\0a",
      "\x1f",
      "a" * 257,
]
    fine = [" CON", "COM0", "COM77", "@CON", "not.CON", "CON。", ".CON", "®" * 250, "ファイル", "a", "a.aaaaaaaa"]

    reserved_or_invalid.each { |name| assert_equal "\\\\?\\C:\\#{name}", Std::WINDOWS.simplified("\\\\?\\C:\\#{name}"), name }
    fine.each { |name| assert_equal "C:\\#{name}", Std::WINDOWS.simplified("\\\\?\\C:\\#{name}"), name }
  end

  def test_dunce_leaves_every_path_alone_off_windows
    assert_equal "\\\\?\\C:\\Windows", Std::UNIX.simplified("\\\\?\\C:\\Windows")
  end

  private def assert_decompositions(std, cases)
    cases.each do |path, iter, has_root, is_absolute, parent, file_name, file_stem, extension|
      assert_equal iter, std.components(path).map(&:as_os_str), "components of #{path.inspect}"
      assert_equal has_root, std.has_root?(path), "has_root of #{path.inspect}"
      assert_equal is_absolute, std.absolute?(path), "is_absolute of #{path.inspect}"
      assert_equal_or_nil parent, std.parent(path), "parent of #{path.inspect}"
      assert_equal_or_nil file_name, std.file_name(path), "file_name of #{path.inspect}"
      assert_equal_or_nil file_stem, std.file_stem(path), "file_stem of #{path.inspect}"
      assert_equal_or_nil extension, std.extension(path), "extension of #{path.inspect}"
    end
  end

  private def assert_equal_or_nil(expected, actual, message)
    expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
  end
end
