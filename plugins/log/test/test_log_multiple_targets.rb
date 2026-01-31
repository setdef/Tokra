# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for multiple log targets.
class TestLogMultipleTargets < Minitest::Test
  def test_logs_to_all_targets
    output1 = StringIO.new
    output2 = StringIO.new
    app = Object.new
    targets = [
      Tokra::Plugins::Log::Target.new(output1),
      Tokra::Plugins::Log::Target.new(output2),
    ]
    plugin = Tokra::Plugins::Log::Plugin.new(app, targets:)

    plugin.info("broadcast")

    assert_match(/broadcast/, output1.string)
    assert_match(/broadcast/, output2.string)
  end

  def test_per_target_level_filtering
    output = StringIO.new
    app = Object.new
    # Level set on Plugin config
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Plugin.new(app, targets: [target], level: :warn)

    plugin.info("info message")
    plugin.warn("warn message")

    refute_match(/info message/, output.string)
    assert_match(/warn message/, output.string)
  end
end
