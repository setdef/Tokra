# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for webview event types: PhysicalPosition, DragDropEvent, WebviewEvent
class TestWebviewEvents < Minitest::Test
  # --- PhysicalPosition ---

  def test_physical_position_stores_x_and_y
    pos = Tokra::PhysicalPosition.new(x: 100.5, y: 200.5)

    assert_equal 100.5, pos.x
    assert_equal 200.5, pos.y
  end

  # --- DragDropEvent ---

  def test_drag_drop_enter_stores_paths_and_position
    pos = Tokra::PhysicalPosition.new(x: 10.0, y: 20.0)
    event = Tokra::DragDropEvent::Enter.new(
      paths: [Pathname.new("/tmp/file.txt")],
      position: pos
    )

    assert_equal [Pathname.new("/tmp/file.txt")], event.paths
    assert_equal pos, event.position
  end

  def test_drag_drop_over_stores_position
    pos = Tokra::PhysicalPosition.new(x: 30.0, y: 40.0)
    event = Tokra::DragDropEvent::Over.new(position: pos)

    assert_equal pos, event.position
  end

  def test_drag_drop_drop_stores_paths_and_position
    pos = Tokra::PhysicalPosition.new(x: 50.0, y: 60.0)
    event = Tokra::DragDropEvent::Drop.new(
      paths: [Pathname.new("/tmp/a.txt"), Pathname.new("/tmp/b.txt")],
      position: pos
    )

    assert_equal 2, event.paths.size
    assert_equal pos, event.position
  end

  def test_drag_drop_leave_has_no_fields
    event = Tokra::DragDropEvent::Leave.new

    assert_instance_of Tokra::DragDropEvent::Leave, event
  end

  # --- WebviewEvent ---

  def test_webview_event_drag_drop_wraps_event
    inner = Tokra::DragDropEvent::Leave.new
    event = Tokra::WebviewEvent::DragDrop.new(event: inner)

    assert_same inner, event.event
  end
end
