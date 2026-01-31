# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for Target class.
class TestLogTarget < Minitest::Test
  def test_rejects_non_shareable_formatter
    output = StringIO.new
    non_shareable = proc { |_sev, _time, _prog, msg| msg }

    error = assert_raises(Ractor::IsolationError) do
      Tokra::Plugins::Log::Target.new(destination: output, formatter: non_shareable)
    end

    assert_match(/formatter/, error.message)
  end

  def test_accepts_shareable_formatter
    output = StringIO.new
    shareable = Ractor.shareable_proc { |_sev, _time, _prog, msg| "#{msg}\n" }

    target = Tokra::Plugins::Log::Target.new(destination: output, formatter: shareable)

    assert_kind_of Tokra::Plugins::Log::Target, target
  end
end
