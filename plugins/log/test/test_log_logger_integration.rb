# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for stdlib Logger integration.
class TestLogLoggerIntegration < Minitest::Test
  def test_formatter_customizes_output_format
    output = StringIO.new
    custom_formatter = Ractor.shareable_proc { |_sev, _time, _prog, msg| "CUSTOM: #{msg}\n" }
    target = Tokra::Plugins::Log::Target.new(output).format(custom_formatter)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .build

    plugin.info("test message")

    assert_equal "CUSTOM: test message\n", output.string
  end

  def test_progname_appears_in_log_entries
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .progname("MyApp")
      .build

    plugin.info("test message")

    assert_match(/MyApp/, output.string)
  end

  def test_datetime_format_customizes_timestamp
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .datetime_format("%Y/%m/%d")
      .build

    plugin.info("test message")

    # Should match our custom format (YYYY/MM/DD) not the default ISO format
    assert_match(%r{\d{4}/\d{2}/\d{2}}, output.string)
    refute_match(/T\d{2}:\d{2}:\d{2}/, output.string) # No ISO time separator
  end

  def test_add_method_with_all_arguments
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .build

    plugin.add(Logger::WARN, "warning message", "CustomProg")

    assert_match(/WARN/, output.string)
    assert_match(/warning message/, output.string)
    assert_match(/CustomProg/, output.string)
  end

  def test_shift_operator_writes_raw_message
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .build

    plugin << "raw message"

    # Raw message should appear without formatting
    assert_equal "raw message", output.string
  end

  def test_with_level_temporarily_changes_level
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Builder.new
      .targets([target])
      .level(:warn)
      .build

    # Debug should be filtered at :warn level
    plugin.debug("should not appear")
    assert_empty output.string

    # But with_level should temporarily allow debug
    plugin.with_level(:debug) do
      plugin.debug("should appear")
    end
    assert_match(/should appear/, output.string)

    # After block, level should be restored
    output.truncate(0)
    output.rewind
    plugin.debug("should not appear again")
    assert_empty output.string
  end
end
