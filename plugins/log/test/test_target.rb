# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for Log::Target fluent API.
class TestLogTarget < Minitest::Test
  def test_accepts_stdout
    target = Tokra::Plugins::Log::Target.new($stdout)
    assert_instance_of Tokra::Plugins::Log::Target, target
    assert_equal $stdout, target.kind
  end

  def test_accepts_pathname
    target = Tokra::Plugins::Log::Target.new(Pathname("logs/app.log"))
    assert_instance_of Tokra::Plugins::Log::Target, target
  end

  def test_filter_returns_self_for_chaining
    target = Tokra::Plugins::Log::Target.new($stdout)
    filter = Ractor.shareable_proc { |msg| !msg.include?("secret") }

    result = target.filter(filter)

    assert_same target, result
  end

  def test_format_returns_self_for_chaining
    target = Tokra::Plugins::Log::Target.new($stdout)
    formatter = Ractor.shareable_proc { |_sev, _time, _prog, msg| "#{msg}\n" }

    result = target.format(formatter)

    assert_same target, result
  end

  def test_rejects_non_shareable_filter
    target = Tokra::Plugins::Log::Target.new($stdout)
    non_shareable = proc { |msg| msg.include?("test") }

    error = assert_raises(Ractor::IsolationError) do
      target.filter(non_shareable)
    end

    assert_match(/filter/, error.message)
  end

  def test_rejects_non_shareable_formatter
    target = Tokra::Plugins::Log::Target.new($stdout)
    non_shareable = proc { |_sev, _time, _prog, msg| msg }

    error = assert_raises(Ractor::IsolationError) do
      target.format(non_shareable)
    end

    assert_match(/formatter/, error.message)
  end

  def test_accepts_shareable_formatter
    output = StringIO.new
    shareable = Ractor.shareable_proc { |_sev, _time, _prog, msg| "#{msg}\n" }

    target = Tokra::Plugins::Log::Target.new(output).format(shareable)

    assert_kind_of Tokra::Plugins::Log::Target, target
  end
end
