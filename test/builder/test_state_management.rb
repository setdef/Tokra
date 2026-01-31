# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Builder state management (manage / state / try_state).
class TestBuilderStateManagement < Minitest::Test
  def test_manage_state_accessible_via_app_handle_in_setup
    state = Object.new
    Thread.current[:retrieved] = nil
    hook = Ractor.shareable_proc { |app|
      Thread.current[:retrieved] = app.handle.state(Object)
    }

    Tokra::Builder.default
      .manage(state)
      .setup(&hook)
      .run(native: StubNative)

    assert_same state, Thread.current[:retrieved]
  end

  def test_try_state_returns_nil_when_not_managed
    Thread.current[:retrieved] = :sentinel
    hook = Ractor.shareable_proc { |app|
      Thread.current[:retrieved] = app.handle.try_state(Object)
    }

    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)

    assert_nil Thread.current[:retrieved]
  end

  def test_state_raises_when_not_managed
    hook = Ractor.shareable_proc { |app|
      Thread.current[:error] = begin
        app.handle.state(Object)
        nil
      rescue KeyError => e
        e
      end
    }
    Tokra::Builder.default
      .setup(&hook)
      .run(native: StubNative)
    assert_instance_of KeyError, Thread.current[:error]
  end
end
