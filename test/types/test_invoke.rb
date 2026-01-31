# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Invoke type.
class TestInvoke < Minitest::Test
  def test_stores_command_and_payload
    invoke = Tokra::Invoke.new(command: "greet", payload: '{"name":"World"}', responder: nil)

    assert_equal "greet", invoke.command
    assert_equal '{"name":"World"}', invoke.payload
  end

  def test_resolve_calls_responder_with_success
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder:)
    invoke.resolve("result")

    assert_equal [[true, "result"]], calls
  end

  def test_reject_calls_responder_with_failure
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder:)
    invoke.reject("error message")

    assert_equal [[false, "error message"]], calls
  end

  def test_only_responds_once
    calls = []
    responder = -> (success, value) { calls << [success, value] }

    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder:)
    invoke.resolve("first")
    invoke.resolve("second")
    invoke.reject("third")

    assert_equal 1, calls.size, "Should only call responder once"
    assert_equal [[true, "first"]], calls
  end

  def test_without_responder_does_not_error
    invoke = Tokra::Invoke.new(command: "cmd", payload: "", responder: nil)

    # Should not raise
    invoke.resolve("value")
    invoke.reject("error")
  end
end
