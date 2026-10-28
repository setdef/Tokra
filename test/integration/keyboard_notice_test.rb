# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/keyboard_notice"

# KeyboardNotice speaks only where a person may be typing, and never in
# these tests: each replaces +say+ with a recorder.
#
# The settle test waits out SETTLE once, about three seconds, since the
# call back is timed by the clock and nothing else.
class KeyboardNoticeTest < Minitest::Test
  def setup
    @saved = ENV.to_h.slice("CI", "TOKRA_QUIET")
    ENV.delete("CI")
    ENV.delete("TOKRA_QUIET")
    @said = []
    @spoken = Thread::Queue.new
  end

  def teardown
    ENV.delete("CI")
    ENV.delete("TOKRA_QUIET")
    ENV.update(@saved)
  end

  def test_ci_silences_it
    ENV["CI"] = "true"
    refute_predicate KeyboardNotice, :speaks?
    assert_nil recording { KeyboardNotice.taking_the_keyboard }
    assert_empty @said
  end

  def test_tokra_quiet_silences_it
    ENV["TOKRA_QUIET"] = "1"
    refute_predicate KeyboardNotice, :speaks?
    assert_nil recording { KeyboardNotice.taking_the_keyboard }
    assert_empty @said
  end

  def test_it_speaks_on_a_mac_with_say_and_neither_variable
    expected = RbConfig::CONFIG["host_os"].include?("darwin") && File.executable?("/usr/bin/say")
    assert_equal expected, KeyboardNotice.speaks?
  end

  def test_without_speech_the_block_still_runs
    ENV["TOKRA_QUIET"] = "1"
    assert_equal :ran, recording { KeyboardNotice.taking_the_keyboard { :ran } }
    assert_empty @said
  end

  # Two blocks in a row are one stretch: one warning before the first, and
  # one call back only once SETTLE seconds pass with neither running.
  def test_a_stretch_is_announced_once_and_called_back_once_it_settles
    KeyboardNotice.stub(:speaks?, true) do
      recording do
        assert_equal 1, KeyboardNotice.taking_the_keyboard { 1 }
        KeyboardNotice.taking_the_keyboard { assert_equal [KeyboardNotice::STEP_AWAY], @said }
        assert_equal [KeyboardNotice::STEP_AWAY], @said, "called back before the stretch settled"
        @spoken.clear
        @spoken.pop(timeout: KeyboardNotice::SETTLE + 5)
      end
    end
    assert_equal [KeyboardNotice::STEP_AWAY, KeyboardNotice::COME_BACK], @said
  end

  private def recording(&)
    KeyboardNotice.stub(:say, -> (words) { @spoken << (@said << words) }, &)
  end
end
