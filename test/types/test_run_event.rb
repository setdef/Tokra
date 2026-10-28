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

  def test_exit_requested_stores_code_and_api
    api = Tokra::ExitRequestApi.new(42)
    event = Tokra::RunEvent::ExitRequested.new(code: 42, api:)
    assert_equal 42, event.code
    assert_same api, event.api
  end

  def test_prevent_exit_marks_the_request_prevented
    api = Tokra::ExitRequestApi.new(nil)
    refute_predicate api, :prevented?
    assert_nil api.prevent_exit
    assert_predicate api, :prevented?
  end

  # app.rs:87-91: a restart cannot be refused.
  def test_prevent_exit_is_ignored_for_the_restart_code
    api = Tokra::ExitRequestApi.new(Tokra::RESTART_EXIT_CODE)
    api.prevent_exit
    refute_predicate api, :prevented?
  end

  def test_restart_exit_code_is_i32_max
    assert_equal (2 ** 31) - 1, Tokra::RESTART_EXIT_CODE
  end
end
