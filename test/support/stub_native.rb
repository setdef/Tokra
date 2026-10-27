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

  # Stub Proxy that records respond() and drop_response() calls
  class Proxy
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

  # Stub Window recording its title and size
  class Window
    attr_reader :title, :size

    def initialize(_event_loop)
      StubNative.windows << self
    end

    def set_title(title) = @title = title
    def set_size(width, height) = @size = [width, height]

    # The tagged Arrays the native window answers for its raw handles
    # (ext/tokra/src/raw_handle.rs). A stub window has no native one, so
    # by default both name raw-window-handle's Unavailable.
    attr_writer :raw_window_handle, :raw_display_handle

    def raw_window_handle = @raw_window_handle || [:Unavailable]
    def raw_display_handle = @raw_display_handle || [:Unavailable]
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
    end

    def eval(js)
      raise "evaluation failed" if js == FAILING_SCRIPT

      @evals << js
    end
  end

  # Stub EventLoop that delivers the injected event (or events) to the
  # callback, then LoopDestroyedEvent, the order tao's loop ends in.
  class EventLoop
    def create_proxy = Proxy.new

    def run(callback)
      injected = Thread.current[:stub_native_event]
      events = injected.is_a?(Array) ? injected : [injected].compact
      events.each { |event| callback.call(event) }
      callback.call(Tokra::Native::LoopDestroyedEvent.new)
    end
  end
end
