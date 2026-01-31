# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::PhysicalPosition coordinate type.
class TestPhysicalPosition < Minitest::Test
  def test_stores_x_and_y
    pos = Tokra::PhysicalPosition.new(100, 200)

    assert_equal 100, pos.x
    assert_equal 200, pos.y
  end

  def test_is_frozen_and_shareable
    pos = Tokra::PhysicalPosition.new(50, 75)

    assert_predicate pos, :frozen?
    assert Ractor.shareable?(pos)
  end
end
