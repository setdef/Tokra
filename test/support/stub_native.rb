# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Stubs for the Native (Rust FFI) boundary.
# EventLoop is configured per-test via thread-local to inject events.
module StubNative
  # Thread-local event queue for test injection
  def self.inject_event(event)
    Thread.current[:stub_native_event] = event
  end

  def self.clear_event
    Thread.current[:stub_native_event] = nil
    Thread.current[:stub_native_responses] = nil
    Thread.current[:stub_native_dropped] = nil
    Thread.current[:stub_native_windows] = nil
    Thread.current[:stub_native_webviews] = nil
    Thread.current[:stub_native_task_wake_ups] = nil
    Thread.current[:stub_native_event_loop_calls] = nil
    Thread.current[:stub_native_exit_code] = nil
  end

  # The status the loop ended with: the code of the exit request the App
  # accepted, 0 for the last window gone, or +nil+ when the loop simply ran
  # out of events.
  def self.exit_code
    Thread.current[:stub_native_exit_code]
  end

  # The calls the event loops received across the run, in order:
  # <tt>[:set_activation_policy, name]</tt> and <tt>[:run]</tt>.
  def self.event_loop_calls
    Thread.current[:stub_native_event_loop_calls] ||= []
  end

  # How many times Proxy#send_task woke the loop across the run.
  def self.task_wake_ups
    Thread.current[:stub_native_task_wake_ups] ||= 0
  end

  # Windows created across the run, recording their title and size.
  def self.windows
    Thread.current[:stub_native_windows] ||= []
  end

  # Protocol responses recorded across the run, observable by tests
  # (the proxy is created inside App#run, so the sink is module-level).
  def self.responses
    Thread.current[:stub_native_responses] ||= []
  end

  # Request ids dropped without a reply (ipc:// key mismatch path),
  # observable by tests the same way as responses.
  def self.dropped
    Thread.current[:stub_native_dropped] ||= []
  end

  # Stub Proxy that records respond() and drop_response() calls, and
  # queues the loop's own requests as the real proxy sends them through
  # tao's channel.
  class Proxy
    def initialize(queue = [])
      @queue = queue
    end

    # Queues the request as Native::Proxy#request_exit does: the loop
    # delivers it as an ExitRequestedEvent.
    def request_exit(code)
      @queue << Tokra::Native::ExitRequestedEvent.new(code)
      nil
    end

    # Queues the window's close request, which the loop delivers as the
    # close button's WindowCloseEvent.
    def request_close
      @queue << Tokra::Native::WindowCloseEvent.new
      nil
    end

    def respond(id, status, headers, body)
      StubNative.responses << [id, status, headers, body]
    end

    def drop_response(id)
      StubNative.dropped << id
    end

    # Counts the wake-up; the test injects the Native::TaskEvent it causes.
    def send_task
      Thread.current[:stub_native_task_wake_ups] = StubNative.task_wake_ups + 1
      nil
    end
  end

  # Stub Window recording its title and size. Closing it queues its
  # WindowDestroyedEvent, as the platform answers tao's dropped window.
  class Window
    attr_reader :size

    def initialize(event_loop)
      @queue = event_loop&.queue || []
      @closed = false
      StubNative.windows << self
    end

    def closed? = @closed

    def close
      return if @closed

      @closed = true
      @queue << Tokra::Native::WindowDestroyedEvent.new
      nil
    end

    # A closed window answers +nil+, as Native::Window#title does.
    def title = @closed ? nil : @title

    def set_title(title) = @closed || @title = title
    def set_size(width, height) = @size = [width, height]
    def set_always_on_top(always_on_top) = @always_on_top = always_on_top
    def set_ignore_cursor_events(ignore) = @ignore_cursor_events = ignore

    # The tagged Arrays the native window answers for its raw handles
    # (ext/tokra/src/raw_handle.rs). A stub window has no native one, so
    # by default both name raw-window-handle's Unavailable.
    attr_writer :raw_window_handle, :raw_display_handle

    def raw_window_handle = (!@closed && @raw_window_handle) || [:Unavailable]
    def raw_display_handle = (!@closed && @raw_display_handle) || [:Unavailable]
  end

  # Stub WebView factory recording initialization scripts and evals
  class WebView
    # A script whose evaluation fails, the way wry's evaluate_script can.
    FAILING_SCRIPT = "throw from wry"

    attr_reader :initialization_scripts, :evals

    def self.new_with_protocol(_, _, scripts) = new(scripts).tap { |webview| instances << webview }

    # Webviews created across the run.
    def self.instances
      Thread.current[:stub_native_webviews] ||= []
    end

    def initialize(scripts = [])
      @initialization_scripts = scripts
      @evals = []
      @closed = false
    end

    def closed? = @closed

    def close
      @closed = true
      nil
    end

    # A closed webview ignores the script, as Native::WebView#eval does.
    def eval(js)
      return if @closed
      raise "evaluation failed" if js == FAILING_SCRIPT

      @evals << js
    end
  end

  # Stub EventLoop that delivers the injected event (or events), and the
  # events the run itself queues, to the callback, then
  # LoopDestroyedEvent, the order tao's loop ends in. An exit the App
  # accepts ends the loop at once, as the native loop's answer does
  # (ext/tokra/src/event_loop.rs).
  class EventLoop
    # Events waiting for the callback; windows and proxies add to it.
    attr_reader :queue

    def initialize
      @queue = []
    end

    def create_proxy = Proxy.new(@queue)

    # Records the policy's name, as tao's macOS loop keeps it for launch.
    # Defined only where the real loop has it, so the stub answers
    # respond_to? as Native::EventLoop does.
    if Tokra::Native::EventLoop.method_defined?(:set_activation_policy)
      def set_activation_policy(name)
        StubNative.event_loop_calls << [:set_activation_policy, name]
        nil
      end
    end

    def run(callback)
      StubNative.event_loop_calls << [:run]
      injected = Thread.current[:stub_native_event]
      @queue.unshift(*(injected.is_a?(Array) ? injected : [injected].compact))
      while (event = @queue.shift)
        answer = callback.call(event)
        break if ends_loop?(event, answer)
      end
      callback.call(Tokra::Native::LoopDestroyedEvent.new)
    end

    # Whether the App's +answer+ to +event+ ends the loop, recording the
    # status the native loop would end with.
    private def ends_loop?(event, answer)
      return false unless answer == true

      case event
      when Tokra::Native::ExitRequestedEvent then Thread.current[:stub_native_exit_code] = event.code
      when Tokra::Native::WindowDestroyedEvent then Thread.current[:stub_native_exit_code] = 0
      else return false
      end
      true
    end
  end
end
