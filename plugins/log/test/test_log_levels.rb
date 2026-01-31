# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for all log levels (debug, info, warn, error, fatal).
class TestLogLevels < Minitest::Test
  def setup
    @output = StringIO.new
    @app = Object.new
    @target = Tokra::Plugins::Log::Target.new(@output)
    @plugin = Tokra::Plugins::Log::Plugin.new(@app, targets: [@target])
  end

  def test_debug_logs_message
    @plugin.debug("debug message")
    assert_match(/DEBUG/, @output.string)
    assert_match(/debug message/, @output.string)
  end

  def test_info_logs_message
    @plugin.info("info message")
    assert_match(/INFO/, @output.string)
    assert_match(/info message/, @output.string)
  end

  def test_warn_logs_message
    @plugin.warn("warn message")
    assert_match(/WARN/, @output.string)
    assert_match(/warn message/, @output.string)
  end

  def test_error_logs_message
    @plugin.error("error message")
    assert_match(/ERROR/, @output.string)
    assert_match(/error message/, @output.string)
  end

  def test_fatal_logs_message
    @plugin.fatal("fatal message")
    assert_match(/FATAL/, @output.string)
    assert_match(/fatal message/, @output.string)
  end

  def test_trace_logs_message
    output = StringIO.new
    target = Tokra::Plugins::Log::Target.new(output)
    plugin = Tokra::Plugins::Log::Plugin.new(@app, targets: [target], level: :trace)

    plugin.trace("trace message")

    assert_match(/TRACE/, output.string)
    assert_match(/trace message/, output.string)
  end
end
