# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# StubNative's recorders belong to one test: a test that runs an App and
# leaves its calls behind must not hand them to the next.
class TestStubNativeReset < Minitest::Test
  def test_a_test_starts_without_the_calls_an_earlier_run_left
    Tokra::Builder.default.run(native: StubNative)
    refute_empty StubNative.event_loop_calls
    refute_empty StubNative.nsapp_calls if Tokra::Native.respond_to?(:init_menu_for_nsapp)

    self.class.new(name).before_setup

    assert_empty StubNative.event_loop_calls
    assert_empty StubNative.nsapp_calls
  end

  # Every recorder lives under a stub_native_ key, so one added later
  # without a line in clear_event fails here.
  def test_the_reset_clears_every_recorder
    source = File.read(File.join(__dir__, "support/stub_native.rb"))
    recorders = source.scan(/:(stub_native_\w+)/).flatten.uniq.map(&:to_sym)
    refute_empty recorders
    recorders.each { |key| Thread.current[key] = [:left_behind] }

    self.class.new(name).before_setup

    assert_equal({}, recorders.to_h { |key| [key, Thread.current[key]] }.compact)
  end
end
