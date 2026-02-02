# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::ResourceTable.
class TestResourceTable < Minitest::Test
  def test_new_creates_instance
    table = Tokra::ResourceTable.new
    assert_instance_of Tokra::ResourceTable, table
  end

  def test_has_returns_false_for_unknown_rid
    table = Tokra::ResourceTable.new
    refute table.has?(42)
  end
end
