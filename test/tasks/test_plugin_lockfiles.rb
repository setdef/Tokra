# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests that each plugin's Gemfile.lock names Windows' platform (Plan 061).
#
# plugins:test installs each plugin's bundle unfrozen. Bundler counts a
# lockfile's ruby platform for every platform but Java's and Windows', so
# on Windows it adds x64-mingw-ucrt to any lockfile without it (bundler
# 4.0.3, rubygems_ext.rb GENERICS and definition.rb add_current_platform),
# and the gate left the tree changed, which refuses the next push.
class TestPluginLockfiles < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_each_plugin_lockfile_names_windows_platform
    lockfiles = Dir.glob("plugins/*/Gemfile.lock", base: ROOT).sort

    refute_empty lockfiles
    lockfiles.each do |path|
      platforms = File.read(File.join(ROOT, path))[/^PLATFORMS\n((?:  .*\n)*)/, 1].to_s.split

      assert_includes platforms, "x64-mingw-ucrt", path
    end
  end
end
