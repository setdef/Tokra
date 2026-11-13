# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# LogLevel, the number a level crosses the wire as, and its conversions
# to and from log's Level (lib.rs:70-120; guest-js/index.ts:14-45).
class TestLogLevel < Minitest::Test
  include LogTest

  def test_each_level_is_numbered_as_tauri_numbers_it
    assert_equal [1, 2, 3, 4, 5],
      [Log::LogLevel::TRACE, Log::LogLevel::DEBUG, Log::LogLevel::INFO, Log::LogLevel::WARN, Log::LogLevel::ERROR]
  end

  def test_a_level_converts_to_its_number_and_back
    %i[trace debug info warn error].each do |level|
      assert_equal level, Log::LogLevel.to_level(Log::LogLevel.from(level))
    end
    assert_equal 4, Log::LogLevel.from(:warn)
  end
end
