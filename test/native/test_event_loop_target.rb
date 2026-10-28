# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Native::EventLoop's window target, against the real extension (plan 041,
# decision 1). Before the loop runs it answers from tao's own loop, in the
# shapes AppHandle reads; the running loop's lent target is checked by the
# window_state fixture.
class TestNativeEventLoopTarget < Minitest::Test
  def setup
    reason = NativeEventLoop.unavailable_reason
    skip reason if reason

    @event_loop = NativeEventLoop.shared
  end

  def test_before_it_runs_the_loop_lists_its_monitors
    monitors = @event_loop.available_monitors
    refute_empty monitors
    name, position, size, work_area, scale_factor = monitors.first
    assert(name.nil? || name.is_a?(String))
    assert_equal 2, position.size
    assert_equal 2, size.size
    assert_equal 2, work_area.size
    assert_kind_of Float, scale_factor
  end

  def test_the_primary_monitor_and_the_monitor_at_its_corner_are_listed
    primary, = @event_loop.primary_monitor
    skip "this platform names no primary monitor" unless primary

    assert_includes @event_loop.available_monitors, primary
    _, (x, y), = primary
    assert_equal [primary], @event_loop.monitor_from_point(x.to_f, y.to_f)
  end

  def test_the_cursor_is_a_pair_of_floats_or_taos_error
    answer = @event_loop.cursor_position
    assert_equal 1, answer.size
    position = answer.first
    skip "this platform cannot read the cursor here" unless position

    assert_equal 2, position.size
    position.each { |coordinate| assert_kind_of Float, coordinate }
  end

  def test_off_the_loops_thread_each_getter_raises_thread_error
    %i[cursor_position primary_monitor available_monitors].each do |getter|
      error = assert_raises(ThreadError) do
        Thread.new do
          Thread.current.report_on_exception = false
          @event_loop.public_send(getter)
        end.value
      end
      assert_equal "Tokra::Native::EventLoop can only be used on the thread that created it", error.message
    end
  end
end
