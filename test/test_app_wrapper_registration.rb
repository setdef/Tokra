# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::App wrapper registration.
class TestAppWrapperRegistration < Minitest::Test
  def test_run_registers_window_in_app_handle
    builder = Tokra::Builder.default
    app = Tokra::App.new(builder, native: StubNative)

    # Run and capture handle via the run callback (which receives handle)
    captured_handle = nil
    app.run { |handle, _event| captured_handle ||= handle }

    refute_nil captured_handle.get_window("main"), "Window wrapper should be registered"
    assert_instance_of Tokra::Window, captured_handle.get_window("main")
  end

  def test_run_registers_webview_in_app_handle
    builder = Tokra::Builder.default
    app = Tokra::App.new(builder, native: StubNative)

    captured_handle = nil
    app.run { |handle, _event| captured_handle ||= handle }

    refute_nil captured_handle.get_webview("main"), "Webview wrapper should be registered"
    assert_instance_of Tokra::Webview, captured_handle.get_webview("main")
  end

  # Stub native module for testing
  module StubNative
    class EventLoop
      def create_proxy; StubProxy.new; end
      def run(_callback); end # Exits immediately
    end

    class Window
      def initialize(_event_loop); end
      def set_title(_title); end
      def set_size(_w, _h); end
    end

    class WebView
      def self.new_with_protocol(_window, _proxy); new; end
      def eval(_script); end
    end

    class Proxy
      def respond(*); end
    end
  end

  StubProxy = StubNative::Proxy
end
