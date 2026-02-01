# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"

# Tests for TimezoneStrategy Data classes (Tauri API parity).
#
# TimezoneStrategy controls whether timestamps use UTC or local time.
# Plugin-level setting passed to formatters.
class TestTimezoneStrategy < Minitest::Test
  TimezoneStrategy = Tokra::Plugins::Log::TimezoneStrategy

  # Data class structure

  def test_use_utc_is_data_class_with_no_fields
    use_utc = TimezoneStrategy::UseUtc.new

    assert_kind_of Data, use_utc
    assert_equal [], use_utc.members
  end

  def test_use_local_is_data_class_with_no_fields
    use_local = TimezoneStrategy::UseLocal.new

    assert_kind_of Data, use_local
    assert_equal [], use_local.members
  end

  # format_time: converts time to appropriate timezone

  def test_use_utc_converts_time_to_utc
    local_time = Time.new(2026, 1, 31, 12, 0, 0, "-06:00")

    result = TimezoneStrategy::UseUtc.new.format_time(local_time)

    assert result.utc?
    assert_equal 18, result.hour # 12:00 CST = 18:00 UTC
  end

  def test_use_local_returns_time_unchanged
    local_time = Time.new(2026, 1, 31, 12, 0, 0, "-06:00")

    result = TimezoneStrategy::UseLocal.new.format_time(local_time)

    assert_same local_time, result
  end

  # Integration: TimezoneStrategy affects log output

  # Shareable formatter that extracts time's UTC status
  UTC_STATUS_FORMATTER = Ractor.make_shareable(
    -> (severity, time, progname, msg) { "utc:#{time.utc?}\n" }
  )

  def test_use_utc_strategy_passes_utc_time_to_formatter
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
      .timezone_strategy(TimezoneStrategy::UseUtc.new)
      .format(UTC_STATUS_FORMATTER)
    builder = Tokra::Plugins::Log::Builder.new

    target.to_logger(builder).info("test")

    assert_equal "utc:true\n", output.string
  end

  def test_use_local_strategy_passes_local_time_to_formatter
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
      .timezone_strategy(TimezoneStrategy::UseLocal.new)
      .format(UTC_STATUS_FORMATTER)
    builder = Tokra::Plugins::Log::Builder.new

    target.to_logger(builder).info("test")

    assert_equal "utc:false\n", output.string
  end
end
