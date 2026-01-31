# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"

# Tests for TauriLevel conversion module.
#
# Validates bidirectional conversion between Ruby Logger severity
# and Tauri LogLevel, ensuring formula correctness at boundaries.
class TestTauriLevel < Minitest::Test
  TauriLevel = Tokra::Plugins::Log::TauriLevel

  # from_ruby: Ruby Logger severity → Tauri LogLevel
  # TRACE=-1→1, DEBUG=0→2, INFO=1→3, WARN=2→4, ERROR=3→5, FATAL/UNKNOWN→5

  def test_from_ruby_trace_maps_to_1
    assert_equal 1, TauriLevel.from_ruby(-1)
  end

  def test_from_ruby_debug_maps_to_2
    assert_equal 2, TauriLevel.from_ruby(0)
  end

  def test_from_ruby_info_maps_to_3
    assert_equal 3, TauriLevel.from_ruby(1)
  end

  def test_from_ruby_warn_maps_to_4
    assert_equal 4, TauriLevel.from_ruby(2)
  end

  def test_from_ruby_error_maps_to_5
    assert_equal 5, TauriLevel.from_ruby(3)
  end

  def test_from_ruby_fatal_clamps_to_5
    assert_equal 5, TauriLevel.from_ruby(4)
  end

  def test_from_ruby_unknown_clamps_to_5
    assert_equal 5, TauriLevel.from_ruby(5)
  end

  # to_ruby: Tauri LogLevel → Ruby Logger severity
  # 1→-1, 2→0, 3→1, 4→2, 5→3

  def test_to_ruby_trace_maps_to_negative_1
    assert_equal(-1, TauriLevel.to_ruby(1))
  end

  def test_to_ruby_debug_maps_to_0
    assert_equal 0, TauriLevel.to_ruby(2)
  end

  def test_to_ruby_info_maps_to_1
    assert_equal 1, TauriLevel.to_ruby(3)
  end

  def test_to_ruby_warn_maps_to_2
    assert_equal 2, TauriLevel.to_ruby(4)
  end

  def test_to_ruby_error_maps_to_3
    assert_equal 3, TauriLevel.to_ruby(5)
  end
end
