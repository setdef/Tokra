# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Builder build and run behavior.
class TestBuilderBuildRun < Minitest::Test
  def test_build_returns_app_instance
    builder = Tokra::Builder.default
    app = builder.build(native: StubNative)
    assert_instance_of Tokra::App, app
  end

  def test_build_creates_new_app_each_time
    builder = Tokra::Builder.default
    app1 = builder.build(native: StubNative)
    app2 = builder.build(native: StubNative)
    refute_same app1, app2
  end

  def test_run_invokes_callback_with_lifecycle_events
    events = []
    Tokra::Builder.default.run(native: StubNative) do |handle, event|
      events << [handle.class, event.class]
    end
    assert_equal [
      [Tokra::AppHandle, Tokra::RunEvent::Ready],
      [Tokra::AppHandle, Tokra::RunEvent::Exit],
    ], events
  end
end
