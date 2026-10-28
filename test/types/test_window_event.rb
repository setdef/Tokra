# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::WindowEvent types.
class TestWindowEvent < Minitest::Test
  def test_close_requested_carries_its_api
    api = Tokra::CloseRequestApi.new
    event = Tokra::WindowEvent::CloseRequested.new(api:)
    assert_same api, event.api
  end

  def test_prevent_close_marks_the_request_prevented
    api = Tokra::CloseRequestApi.new
    refute_predicate api, :prevented?
    assert_nil api.prevent_close
    assert_predicate api, :prevented?
  end

  def test_destroyed_exists
    event = Tokra::WindowEvent::Destroyed.new
    assert_instance_of Tokra::WindowEvent::Destroyed, event
  end

  def test_focused_stores_value
    event = Tokra::WindowEvent::Focused.new(focused: true)
    assert event.focused
  end

  def test_moved_stores_coordinates
    event = Tokra::WindowEvent::Moved.new(x: 100, y: 200)
    assert_equal 100, event.x
    assert_equal 200, event.y
  end

  def test_resized_stores_dimensions
    event = Tokra::WindowEvent::Resized.new(width: 800, height: 600)
    assert_equal 800, event.width
    assert_equal 600, event.height
  end
end
