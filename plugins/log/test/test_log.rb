# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tests for Log::Plugin core functionality.
class TestLogPlugin < Minitest::Test
  def test_name_returns_log
    plugin = Tokra::Plugins::Log::Builder.new.build
    assert_equal "log", plugin.name
  end

  def test_info_logs_to_target
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .build

    plugin.info("test message")

    assert_match(/test message/, output.string)
  end
end
