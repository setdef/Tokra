# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for per-target custom formatting via fluent API.
class TestLogTargetFormatting < Minitest::Test
  def test_target_format_customizes_output
    output = StringIO.new
    app = Object.new
    formatter = Ractor.shareable_proc { |_sev, _time, _prog, msg| ">>> #{msg}\n" }
    target = Tokra::Plugins::Log::Target.new(output).format(formatter)
    plugin = Tokra::Plugins::Log::Plugin.new(app, targets: [target])

    plugin.info("formatted message")

    assert_equal ">>> formatted message\n", output.string
  end

  def test_format_receives_severity_time_progname_msg
    output = StringIO.new
    app = Object.new
    # Formatter that includes all args in output to verify they're passed correctly
    formatter = Ractor.shareable_proc do |sev, time, prog, msg|
      "[#{sev}] #{time.strftime('%Y')} #{prog}: #{msg}\n"
    end
    target = Tokra::Plugins::Log::Target.new(output).format(formatter)
    plugin = Tokra::Plugins::Log::Plugin.new(app, targets: [target], progname: "MyApp")

    plugin.info("test message")

    # Verify formatter received all expected arguments and format was used
    assert_match(/^\[INFO\] 202\d MyApp: test message\n$/, output.string)
  end
end
