# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::RunEvent types.
class TestRunEvent < Minitest::Test
  def test_ready_is_data_value
    event = Tokra::RunEvent::Ready.new
    assert_instance_of Tokra::RunEvent::Ready, event
  end

  def test_exit_is_data_value
    event = Tokra::RunEvent::Exit.new
    assert_instance_of Tokra::RunEvent::Exit, event
  end

  def test_exit_requested_stores_code
    event = Tokra::RunEvent::ExitRequested.new(code: 42)
    assert_equal 42, event.code
  end
end
