# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::DragDropEvent types (Enter, Over, Drop, Leave).
class TestDragDropEvent < Minitest::Test
  def test_enter_stores_paths_and_position
    pos = Tokra::PhysicalPosition.new(10, 20)
    event = Tokra::DragDropEvent::Enter.new(
      [Pathname.new("/tmp/file.txt")],
      pos
    )

    assert_equal [Pathname.new("/tmp/file.txt")], event.paths
    assert_equal pos, event.position
  end

  def test_over_stores_position
    pos = Tokra::PhysicalPosition.new(30, 40)
    event = Tokra::DragDropEvent::Over.new(pos)

    assert_equal pos, event.position
  end

  def test_drop_stores_paths_and_position
    pos = Tokra::PhysicalPosition.new(50, 60)
    event = Tokra::DragDropEvent::Drop.new(
      [Pathname.new("/tmp/a.txt"), Pathname.new("/tmp/b.txt")],
      pos
    )

    assert_equal 2, event.paths.size
    assert_equal pos, event.position
  end

  def test_leave_has_no_fields
    event = Tokra::DragDropEvent::Leave.new

    assert_instance_of Tokra::DragDropEvent::Leave, event
  end

  def test_all_variants_are_frozen_and_shareable
    pos = Tokra::PhysicalPosition.new(0, 0)
    paths = Ractor.make_shareable([Pathname.new("/tmp/x")])

    [
      Tokra::DragDropEvent::Enter.new(paths, pos),
      Tokra::DragDropEvent::Over.new(pos),
      Tokra::DragDropEvent::Drop.new(paths, pos),
      Tokra::DragDropEvent::Leave.new,
    ].each do |event|
      assert_predicate event, :frozen?, "#{event.class} should be frozen"
      assert Ractor.shareable?(event), "#{event.class} should be shareable"
    end
  end
end
