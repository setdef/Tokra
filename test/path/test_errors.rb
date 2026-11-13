# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# The errors the path API raises, with tauri::Error's messages
# (error.rs:115-132), which a page's path call rejects with.
class TestPathErrors < Minitest::Test
  def test_each_error_has_tauris_message
    {
      Tokra::Error::UnknownPath => "unknown path",
      Tokra::Error::NoParent => "path does not have a parent",
      Tokra::Error::NoExtension => "path does not have an extension",
      Tokra::Error::NoBasename => "path does not have a basename",
    }.each do |klass, message|
      error = klass.new

      assert_equal message, error.message
      assert_kind_of Tokra::Error, error
    end
  end

  def test_current_dir_wraps_the_io_error
    error = Tokra::Error::CurrentDir.new("No such file or directory (os error 2)")

    assert_equal "failed to read current dir: No such file or directory (os error 2)", error.message
    assert_kind_of Tokra::Error, error
  end
end
