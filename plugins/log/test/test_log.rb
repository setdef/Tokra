# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for Log::Plugin.
class TestLogPlugin < Minitest::Test
  def test_name_returns_log
    app = Object.new
    plugin = Tokra::Plugins::Log::Plugin.new(app)
    assert_equal "log", plugin.name
  end

  def test_info_logs_to_target
    output = StringIO.new
    app = Object.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Plugin.new(app, targets: [target])

    plugin.info("test message")

    assert_match(/test message/, output.string)
  end
end
