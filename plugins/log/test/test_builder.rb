# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tests for Log::Builder fluent API.
#
# TDD tests following Tarlinder-style: verify behavior, not implementation.
class TestBuilder < Minitest::Test
  def test_new_creates_builder
    builder = Tokra::Plugins::Log::Builder.new

    assert_kind_of Tokra::Plugins::Log::Builder, builder
  end

  def test_targets_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new
    target = Tokra::Plugins::Log::Target.new($stdout)

    result = builder.targets([target])

    assert_same builder, result
  end

  def test_target_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new
    target = Tokra::Plugins::Log::Target.new($stdout)

    result = builder.target(target)

    assert_same builder, result
  end

  def test_level_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new

    result = builder.level(:debug)

    assert_same builder, result
  end

  def test_rotation_strategy_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new
    strategy = Tokra::Plugins::Log::RotationStrategy::KeepOne.new

    result = builder.rotation_strategy(strategy)

    assert_same builder, result
  end

  def test_timezone_strategy_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new
    strategy = Tokra::Plugins::Log::TimezoneStrategy::UseUtc.new

    result = builder.timezone_strategy(strategy)

    assert_same builder, result
  end

  def test_max_file_size_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new

    result = builder.max_file_size(10_000_000)

    assert_same builder, result
  end

  def test_clear_targets_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new

    result = builder.clear_targets

    assert_same builder, result
  end

  def test_skip_logger_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new

    result = builder.skip_logger

    assert_same builder, result
  end

  def test_build_returns_plugin
    builder = Tokra::Plugins::Log::Builder.new
      .targets([Tokra::Plugins::Log::Target.new($stdout)])
      .level(:debug)

    plugin = builder.build

    assert_kind_of Tokra::Plugins::Log::Plugin, plugin
  end

  def test_progname_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new

    result = builder.progname("my-app")

    assert_same builder, result
  end

  def test_datetime_format_returns_self_for_chaining
    builder = Tokra::Plugins::Log::Builder.new

    result = builder.datetime_format("%Y-%m-%d %H:%M:%S")

    assert_same builder, result
  end

  SIMPLE_FORMATTER = Ractor.make_shareable(
    -> (sev, time, prog, msg) { "FORMATTED: #{msg}\n" }
  )

  def test_format_applies_formatter_to_built_plugin
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)

    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .format(SIMPLE_FORMATTER)
      .build

    plugin.info("hello")

    assert_equal "FORMATTED: hello\n", output.string
  end

  FILTER_REJECTS_SECRET = Ractor.make_shareable(
    -> (msg) { !msg.include?("SECRET") }
  )

  def test_filter_rejects_matching_messages
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)

    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .filter(FILTER_REJECTS_SECRET)
      .build

    plugin.info("public info")
    plugin.info("SECRET data")
    plugin.info("more public info")

    assert_includes output.string, "public info", "non-matching messages should be logged"
    assert_includes output.string, "more public info", "non-matching messages should be logged"
    refute_includes output.string, "SECRET", "matching messages should be rejected"
  end

  def test_with_colors_raises_not_implemented_error
    builder = Tokra::Plugins::Log::Builder.new

    error = assert_raises(NotImplementedError) { builder.with_colors({}) }

    assert_includes error.message, "Logger",
      "error should explain Ruby's Logger is not color-aware"
  end
end
