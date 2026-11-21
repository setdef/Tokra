# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"

# Tests that RuboCop judges line endings only where the checkout cannot
# change them (Plan 061). The repository holds LF. On Windows git writes
# the working tree with CRLF or LF as each clone's core.autocrlf says, so
# Layout/EndOfLine's native style would pass one Windows clone and fail
# every file of another with the same commit. RuboCop reads the
# configuration in a Ruby of its own, since loading it here would add
# modules to the test process that tasks/rbs_parity.rb's tests walk.
class TestRubocopLineEndings < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_layout_end_of_line_is_off_on_windows_alone
    script = 'cop = RuboCop::ConfigLoader.configuration_from_file(ARGV[0]).for_cop("Layout/EndOfLine"); ' \
      'print cop["Enabled"], " ", cop["EnforcedStyle"]'
    # bundler/setup before rubocop, which would otherwise load the Ruby's own
    # default gems before RUBYOPT's bundler/setup runs (Plan 069).
    printed, status = Open3.capture2e(RbConfig.ruby, "-rbundler/setup", "-rrubocop", "-e", script, File.join(ROOT, ".rubocop.yml"))

    assert_predicate status, :success?, printed
    assert_equal "#{!Gem.win_platform?} native", printed
  end
end
