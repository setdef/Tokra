# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tests for per-target filtering.
class TestLogTargetFiltering < Minitest::Test
  def test_target_filter_blocks_matching_messages
    output = StringIO.new
    # Filter that blocks messages containing "secret"
    filter = Ractor.shareable_proc { |msg| !msg.include?("secret") }
    target = Tokra::Plugins::Log::Target.new(output).filter(filter)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .build

    plugin.info("public info")
    plugin.info("secret password")

    assert_match(/public info/, output.string)
    refute_match(/secret/, output.string)
  end

  def test_target_filter_passes_non_matching_messages
    output = StringIO.new
    # Filter that only allows error-level keywords
    filter = Ractor.shareable_proc { |msg| msg.include?("ERROR") }
    target = Tokra::Plugins::Log::Target.new(output).filter(filter)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .build

    plugin.info("normal message")
    plugin.info("ERROR: something bad")

    refute_match(/normal message/, output.string)
    assert_match(/ERROR/, output.string)
  end

  def test_filter_works_with_add_method
    output = StringIO.new
    filter = Ractor.shareable_proc { |msg| msg.include?("allowed") }
    target = Tokra::Plugins::Log::Target.new(output).filter(filter)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .build

    plugin.add(Logger::INFO, "blocked message")
    plugin.add(Logger::INFO, "allowed message")

    refute_match(/blocked/, output.string)
    assert_match(/allowed/, output.string)
  end
end
