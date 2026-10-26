# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"

# How defaultPath becomes the dialog's starting folder and file name
# (commands.rs:100-120), and how a picked Windows path is simplified
# (dunce 1.0.5 src/lib.rs:53-60, 145-182). The dialog is read back through
# rfd's Debug text.
class TestDefaultPath < Minitest::Test
  include DialogTest

  def setup
    @dir = Dir.mktmpdir("tokra-dialog")
    File.write(File.join(@dir, "notes.txt"), "")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # [starting_directory, file_name] as rfd's Debug text shows them.
  private def start_for(default_path)
    builder = Dialog::Commands.set_default_path(new_dialog.file, default_path)
    debug = builder.to_async_file_dialog.inspect
    [debug[/starting_directory: (None|Some\("[^"]*"\))/, 1], debug[/file_name: (None|Some\("[^"]*"\))/, 1]]
  end

  # rfd's Debug text for a path, with this platform's separators: on
  # Windows the components are joined with backslashes, which Debug escapes.
  private def some(path)
    path = path.tr("/", "\\") if Gem.win_platform?
    %(Some("#{path.gsub('\\') { '\\\\' }}"))
  end

  def test_an_existing_directory_is_the_starting_folder
    assert_equal [some(@dir), "None"], start_for(@dir)
  end

  def test_an_existing_file_splits_into_folder_and_name
    assert_equal [some(@dir), 'Some("notes.txt")'], start_for(File.join(@dir, "notes.txt"))
  end

  def test_a_missing_path_splits_into_folder_and_name
    assert_equal [some("#{@dir}/new"), 'Some("out.txt")'], start_for(File.join(@dir, "new", "out.txt"))
  end

  # A bare name has an empty parent, which Tauri does not set.
  def test_a_bare_name_sets_only_the_file_name
    assert_equal ["None", 'Some("report.pdf")'], start_for("report.pdf")
  end

  # Rust's Path::components drops repeated separators, a trailing one,
  # and "." after the start.
  def test_the_path_is_normalized_as_rusts_components_do
    assert_equal [some(@dir), 'Some("notes.txt")'], start_for("#{@dir}//./notes.txt")
    assert_equal [some(@dir), "None"], start_for("#{@dir}/")
    assert_equal ['Some(".")', 'Some("x.txt")'], start_for("./x.txt")
  end

  # A path with no file name (it ends in "..", or is the root) is the
  # starting folder as it is.
  def test_a_path_without_a_file_name_is_the_folder
    assert_equal [some("/"), "None"], start_for("/")
    assert_equal [some("missing/.."), "None"], start_for("missing/..")
  end

  # dunce strips \\?\ from a verbatim disk path when every component is a
  # plain, valid, unreserved file name and the path fits in 260 units.
  def test_dunce_strips_a_verbatim_prefix_only_when_safe
    safe = Dialog::Dunce.method(:safe_to_strip_unc?)
    assert safe.call("\\\\?\\C:\\Users\\me\\notes.txt")
    assert safe.call("\\\\?\\C:\\")
    refute safe.call("C:\\Users\\me"), "not verbatim"
    refute safe.call("\\\\?\\UNC\\server\\share"), "verbatim UNC"
    refute safe.call("\\\\?\\C:\\Users\\con.txt"), "reserved name"
    refute safe.call("\\\\?\\C:\\Users\\a:b"), "invalid character"
    refute safe.call("\\\\?\\C:\\Users\\dot."), "trailing dot"
    refute safe.call("\\\\?\\C:\\a\\..\\b"), "parent component"
    refute safe.call("\\\\?\\C:\\#{'a' * 256}"), "name over 255"
    refute safe.call("\\\\?\\C:\\#{(['a' * 200] * 2).join('\\')}"), "path over 260"
  end

  def test_simplified_changes_nothing_off_windows
    skip "Windows strips the prefix" if Gem.win_platform?
    assert_equal "\\\\?\\C:\\x", Dialog::Commands.simplified("\\\\?\\C:\\x")
  end
end
