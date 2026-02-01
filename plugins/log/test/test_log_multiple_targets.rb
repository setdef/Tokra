# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tests for multiple log targets.
class TestLogMultipleTargets < Minitest::Test
  def test_logs_to_all_targets
    output1 = StringIO.new
    output2 = StringIO.new
    targets = [
      Tokra::Plugins::Log::Target.new(output1),
      Tokra::Plugins::Log::Target.new(output2),
    ]
    plugin = Tokra::Plugins::Log::Builder.new
      .targets(targets)
      .build

    plugin.info("broadcast")

    assert_match(/broadcast/, output1.string)
    assert_match(/broadcast/, output2.string)
  end

  def test_per_target_level_filtering
    output = StringIO.new
    # Level set on Builder
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .level(:warn)
      .build

    plugin.info("info message")
    plugin.warn("warn message")

    refute_match(/info message/, output.string)
    assert_match(/warn message/, output.string)
  end
end
