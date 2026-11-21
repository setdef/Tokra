# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"

# Tests that the bundle loads one strscan (Plan 069).
#
# Ruby 4.1's default strscan has a Ruby entry point, strscan.rb, and Ruby
# looks for strscan.rb along the whole load path before any strscan.so.
# Under a bundle that locked strscan 3.1.7, which has only the extension,
# require "strscan" (rbs and steep's) found Ruby's own strscan.rb, which
# loaded the bundle's extension, and with it 3.1.7's strscan/strscan.rb,
# and then its own, so every test process warned that scan_integer was
# defined twice. strscan 3.1.8 ships its own strscan.rb, which the bundle
# finds first.
class TestStrscan < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_require_strscan_loads_one_copy
    printed, status = Open3.capture2e(RbConfig.ruby, "-w", "-rbundler/setup", "-e", <<~RUBY, chdir: ROOT)
      require "strscan"
      puts $LOADED_FEATURES.grep(%r{/strscan/strscan\\.rb\\z})
    RUBY

    assert_predicate status, :success?, printed
    assert_equal 1, printed.lines.grep(%r{/strscan/strscan\.rb$}).size, printed
    refute_includes printed, "warning", printed
  end
end
