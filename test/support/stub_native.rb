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
  end

  # Stub Proxy that records respond() calls
  class Proxy
    attr_reader :responses

    def initialize = @responses = []
    def respond(id, status, headers, body) = @responses << [id, status, headers, body]
  end

  # Stub Window
  Window = Struct.new(:event_loop) do
    def set_title(_) = nil
    def set_size(_, _) = nil
  end

  # Stub WebView factory
  class WebView
    def self.new_with_protocol(_, _) = new
  end

  # Stub EventLoop that delivers injected event to callback
  class EventLoop
    def create_proxy = Proxy.new

    def run(callback)
      callback.call(Thread.current[:stub_native_event]) if Thread.current[:stub_native_event]
    end
  end
end
