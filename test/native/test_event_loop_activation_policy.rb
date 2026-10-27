# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/native_event_loop"

# Native::EventLoop#set_activation_policy, tao's
# EventLoopExtMacOS::set_activation_policy (tao 0.34.5
# src/platform/macos.rs:310-319, 341-345). tao keeps the policy until AppKit
# finishes launching, so on a loop that never runs it changes nothing
# visible. The real effect is checked on every real-window test:
# RealApp::TestCase#assert_finished (test/integration/support/real_app.rb)
# fails a fixture that was ever the frontmost app, as
# test/integration/support/frontmost.rb reads it.
class TestNativeEventLoopActivationPolicy < Minitest::Test
  def setup
    skip "tao defines set_activation_policy only on macOS" unless RbConfig::CONFIG["host_os"].include?("darwin")
    @event_loop = NativeEventLoop.shared
  end

  def test_takes_each_variant_by_name
    %w[Regular Accessory Prohibited Regular].each do |name|
      assert_nil @event_loop.set_activation_policy(name)
    end
  end

  def test_rejects_any_other_name
    error = assert_raises(ArgumentError) { @event_loop.set_activation_policy("Background") }
    assert_equal 'unknown activation policy: "Background"', error.message
  end

  def test_answers_only_the_loops_thread
    error = Thread.new do
      @event_loop.set_activation_policy("Regular")
      nil
    rescue ThreadError => e
      e
    end.value

    assert_instance_of ThreadError, error
    assert_equal "Tokra::Native::EventLoop can only be used on the thread that created it", error.message
  end
end
