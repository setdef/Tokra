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
  end

  # Stub Window
  Window = Struct.new(:event_loop) do
    def set_title(_) = nil
    def set_size(_, _) = nil
  end

  # Stub WebView factory recording initialization scripts and evals
  class WebView
    attr_reader :initialization_scripts, :evals

    def self.new_with_protocol(_, _, scripts) = new(scripts)

    def initialize(scripts = [])
      @initialization_scripts = scripts
      @evals = []
    end

    def eval(js) = @evals << js
  end

  # Stub EventLoop that delivers injected event to callback
  class EventLoop
    def create_proxy = Proxy.new

    def run(callback)
      callback.call(Thread.current[:stub_native_event]) if Thread.current[:stub_native_event]
    end
  end
end
