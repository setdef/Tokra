# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Builder setup hook behavior.
# Verifies that Builder#setup hook is called when App#run executes.
class TestBuilderSetupHook < Minitest::Test
  def test_setup_hook_is_called_during_run
    Thread.current[:setup_called] = false
    Thread.current[:app_received] = nil
    hook = Ractor.shareable_proc { |app|
      Thread.current[:setup_called] = true
      Thread.current[:app_received] = app
    }
    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)

    assert Thread.current[:setup_called], "setup hook should be called"
    assert_instance_of Tokra::App, Thread.current[:app_received]
  end

  def test_setup_hook_is_called_when_app_runs
    Thread.current[:setup_app] = nil
    hook = Ractor.shareable_proc { |app| Thread.current[:setup_app] = app }

    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)

    assert_instance_of Tokra::App, Thread.current[:setup_app]
  end

  def test_setup_hook_is_called_before_ready_event
    Thread.current[:order] = []
    setup_hook = Ractor.shareable_proc { |_app| Thread.current[:order] << :setup }

    Tokra::Builder.default
      .setup(&setup_hook)
      .run(native: StubNative) { |_handle, event|
        Thread.current[:order] << :ready if event.is_a?(Tokra::RunEvent::Ready)
      }

    assert_equal [:setup, :ready], Thread.current[:order]
  end
end
