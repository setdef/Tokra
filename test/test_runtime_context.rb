# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "timeout"

# Tests for Tokra::RuntimeContext, the port of tauri-runtime-wry's Context
# dispatcher (send_user_message, getter!, Message::Task). Real threads call
# it; the proxy only records the wake-ups the native loop would deliver as
# Native::TaskEvent, and the test's own thread plays the main thread.
class TestRuntimeContext < Minitest::Test
  # Records each wake-up, like Native::Proxy#send_task, and fails like it
  # once the loop is gone.
  class RecordingProxy
    attr_reader :sent

    def initialize
      @sent = 0
      @closed = false
    end

    def send_task
      raise "Failed to send task event: event loop closed" if @closed

      @sent += 1
      nil
    end

    def close!
      @closed = true
    end
  end

  FAILED_TO_SEND = "runtime error: failed to send message to the webview"
  FAILED_TO_RECEIVE = "runtime error: failed to receive message from webview"

  def setup
    @proxy = RecordingProxy.new
    @context = Tokra::RuntimeContext.new
    @context.attach(@proxy)
  end

  # Waits until the background thread has queued its task and woken the
  # loop, the moment a real loop would deliver Native::TaskEvent.
  def wait_for_wake_ups(count)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until @proxy.sent >= count
      flunk "no wake-up after 5 s (sent #{@proxy.sent})" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Thread.pass
    end
  end

  def test_a_call_on_the_main_thread_runs_at_once_without_waking_the_loop
    ran_on = nil
    @context.run_on_main_thread { ran_on = Thread.current }

    assert_same Thread.current, ran_on
    assert_equal 0, @proxy.sent
  end

  def test_a_call_from_another_thread_runs_on_the_main_thread_when_the_loop_handles_it
    ran_on = nil
    Thread.new { @context.run_on_main_thread { ran_on = Thread.current } }.join

    assert_nil ran_on, "the task must wait for the loop, not run on the caller"
    assert_equal 1, @proxy.sent

    @context.handle_task
    assert_same Thread.current, ran_on
  end

  def test_tasks_run_in_the_order_they_were_sent
    order = []
    Thread.new do
      @context.run_on_main_thread { order << 1 }
      @context.run_on_main_thread { order << 2 }
    end.join

    2.times { @context.handle_task }
    assert_equal [1, 2], order
  end

  def test_run_on_main_thread_returns_nil
    assert_nil @context.run_on_main_thread { :ignored }
    assert_nil Thread.new { @context.run_on_main_thread { :ignored } }.value
  end

  def test_a_getter_from_another_thread_waits_for_the_main_thread_and_returns_its_value
    caller = Thread.new { @context.getter { Thread.current } }
    wait_for_wake_ups(1)

    @context.handle_task
    assert_same Thread.current, caller.value
  end

  # A main-thread getter that waited for the loop would wait on itself.
  def test_a_getter_on_the_main_thread_runs_at_once
    assert_equal 42, Timeout.timeout(5) { @context.getter { 42 } }
    assert_equal 0, @proxy.sent
  end

  def test_a_getter_re_raises_what_the_query_raised_in_the_caller
    caller = Thread.new do
      @context.getter { raise ArgumentError, "bad query" }
    rescue ArgumentError => e
      e
    end
    wait_for_wake_ups(1)

    @context.handle_task
    error = caller.value
    assert_instance_of ArgumentError, error
    assert_equal "bad query", error.message
  end

  def test_tasks_sent_before_the_loop_exists_wake_it_once_it_attaches
    context = Tokra::RuntimeContext.new
    ran = []
    Thread.new do
      context.run_on_main_thread { ran << :first }
      context.run_on_main_thread { ran << :second }
    end.join

    proxy = RecordingProxy.new
    context.attach(proxy)
    assert_equal 2, proxy.sent, "one wake-up per queued task"

    2.times { context.handle_task }
    assert_equal [:first, :second], ran
  end

  def test_closing_fails_a_waiting_getter_with_failed_to_receive_message
    caller = Thread.new do
      @context.getter { :never }
    rescue Tokra::Error::Runtime => e
      e
    end
    wait_for_wake_ups(1)
    Thread.pass until caller.status == "sleep"

    @context.close
    error = caller.join(5)&.value
    refute_nil error, "the getter still waits after close"
    assert_instance_of Tokra::Error::Runtime, error
    assert_equal FAILED_TO_RECEIVE, error.message
  end

  def test_after_close_a_call_from_another_thread_fails_with_failed_to_send_message
    @context.close

    error = Thread.new do
      @context.run_on_main_thread { :never }
    rescue Tokra::Error::Runtime => e
      e
    end.value
    assert_equal FAILED_TO_SEND, error.message

    error = Thread.new do
      @context.getter { :never }
    rescue Tokra::Error::Runtime => e
      e
    end.value
    assert_equal FAILED_TO_SEND, error.message
    assert_equal 0, @proxy.sent
  end

  def test_after_close_a_call_on_the_main_thread_still_runs_at_once
    @context.close

    assert_equal :ran, Timeout.timeout(5) { @context.getter { :ran } }
  end

  def test_a_failed_wake_up_fails_with_failed_to_send_message_and_leaves_nothing_queued
    @proxy.close!
    ran = false

    error = Thread.new do
      @context.run_on_main_thread { ran = true }
    rescue Tokra::Error::Runtime => e
      e
    end.value
    assert_equal FAILED_TO_SEND, error.message

    @context.handle_task
    refute ran, "a task whose wake-up failed must not run later"
  end

  def test_handle_task_with_nothing_queued_does_nothing
    assert_nil @context.handle_task
  end

  def test_main_thread_is_the_thread_that_built_the_context_until_one_attaches
    context = Tokra::RuntimeContext.new
    assert context.main_thread?
    refute Thread.new { context.main_thread? }.value
  end

  def test_attaching_makes_the_attaching_thread_the_main_thread
    context = Tokra::RuntimeContext.new
    runner = Thread.new do
      context.attach(RecordingProxy.new)
      context.main_thread?
    end

    assert runner.value, "the thread that runs the loop is the main thread"
    refute context.main_thread?, "the building thread no longer is"
  end

  def test_a_getter_keeps_an_exception_that_is_not_a_standard_error_on_the_main_thread
    caller = Thread.new do
      @context.getter { raise Interrupt }
    rescue Tokra::Error::Runtime => e
      e
    end
    wait_for_wake_ups(1)

    assert_raises(Interrupt) { @context.handle_task }
    assert_equal FAILED_TO_RECEIVE, caller.value.message, "the caller gets no answer, not the Interrupt"
  end
end
