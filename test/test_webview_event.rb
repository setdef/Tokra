# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::WebviewEvent types.
class TestWebviewEvent < Minitest::Test
  def test_drag_drop_wraps_event
    inner = Tokra::DragDropEvent::Leave.new
    event = Tokra::WebviewEvent::DragDrop.new(inner)

    assert_same inner, event.event
  end

  def test_drag_drop_is_frozen_and_shareable
    inner = Tokra::DragDropEvent::Leave.new
    event = Tokra::WebviewEvent::DragDrop.new(inner)

    assert_predicate event, :frozen?
    assert Ractor.shareable?(event)
  end
end
