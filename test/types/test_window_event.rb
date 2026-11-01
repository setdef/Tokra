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

  def test_moved_carries_a_physical_position
    position = Tokra::PhysicalPosition.new(x: 100, y: 200)
    assert_equal position, Tokra::WindowEvent::Moved.new(position).position
  end

  def test_resized_carries_a_physical_size
    size = Tokra::PhysicalSize.new(width: 800, height: 600)
    assert_equal size, Tokra::WindowEvent::Resized.new(size).size
  end

  def test_scale_factor_changed_carries_both_fields
    size = Tokra::PhysicalSize.new(width: 800, height: 600)
    event = Tokra::WindowEvent::ScaleFactorChanged.new(scale_factor: 2.0, new_inner_size: size)
    assert_in_delta 2.0, event.scale_factor
    assert_equal size, event.new_inner_size
  end

  def test_drag_drop_carries_its_event
    inner = Tokra::DragDropEvent::Leave.new
    assert_same inner, Tokra::WindowEvent::DragDrop.new(inner).event
  end
end
