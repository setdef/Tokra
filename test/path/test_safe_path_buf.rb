# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Path::SafePathBuf refuses a path that climbs out with "..", as
# Tauri's does (path/mod.rs:29-84), with its examples as the cases.
class TestSafePathBuf < Minitest::Test
  S = Tokra::Path::SafePathBuf
  MESSAGE = "cannot traverse directory, rewrite the path without the use of `../`"

  def test_tauris_examples
    ["../secret.txt", "/home/user/stuff/../secret.txt"].each do |path|
      error = assert_raises(ArgumentError, path) { S.new(path) }
      assert_equal MESSAGE, error.message
    end
    ["./file.txt", "/home/user/secret.txt"].each { |path| assert_equal path, S.new(path).display }
  end

  def test_a_name_with_dots_is_no_traversal
    assert_equal "a/..b/c..", S.new("a/..b/c..").display
  end

  def test_it_is_a_path
    safe = S.new("/home/user/a.txt")

    assert_equal "/home/user/a.txt", safe.to_path
    assert_equal "/home/user/a.txt", safe.to_s
    assert_equal "/home/user/a.txt", File.path(safe)
  end

  def test_a_pathname_is_taken_as_its_path
    assert_equal "a/b", S.new(Pathname.new("a/b")).display
  end

  # The Deserialize impl reads a PathBuf, then checks it (mod.rs:76-84):
  # serde's "path string", then the custom message.
  def test_a_command_argument_reads_as_tauris_does
    assert_equal "a/b", S.deserialize("a/b").display

    traversal = assert_raises(Tokra::Ipc::CommandItem::Mismatch) { S.deserialize("../a") }
    assert_equal MESSAGE, traversal.message
    number = assert_raises(Tokra::Ipc::CommandItem::Mismatch) { S.deserialize(1) }
    assert_equal "invalid type: integer `1`, expected path string", number.message
  end

  # On Windows a backslash separates too, so "..\\" climbs there and not
  # on Unix.
  def test_each_platform_finds_its_own_parent_components
    refute S.traverses?("..\\secret.txt", Tokra::Path::Std::UNIX)
    assert S.traverses?("..\\secret.txt", Tokra::Path::Std::WINDOWS)
    assert S.traverses?("C:\\a\\..\\b", Tokra::Path::Std::WINDOWS)
  end
end
