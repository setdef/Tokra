# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Native::WakeUpEvent
class TestNativeWakeUpEvent < Minitest::Test
  def test_is_defined
    assert defined?(Tokra::Native::WakeUpEvent), "WakeUpEvent should be defined"
  end

  def test_new_accepts_payload
    event = Tokra::Native::WakeUpEvent.new("worker response")

    assert_kind_of Tokra::Native::WakeUpEvent, event
  end

  def test_payload_returns_stored_string
    event = Tokra::Native::WakeUpEvent.new("response data")

    assert_equal "response data", event.payload
  end

  def test_payload_preserves_json
    json_payload = '{"status":"ok","data":[1,2,3]}'
    event = Tokra::Native::WakeUpEvent.new(json_payload)

    assert_equal json_payload, event.payload
  end
end
