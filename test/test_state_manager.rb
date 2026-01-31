# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

class TestStateManager < Minitest::Test
  def test_set_stores_by_class
    manager = Tokra::StateManager.new
    state = Object.new

    assert manager.set(state)
  end

  def test_set_returns_false_if_already_set
    manager = Tokra::StateManager.new
    state1 = Object.new
    state2 = Object.new

    assert manager.set(state1)
    refute manager.set(state2)
  end

  def test_get_returns_stored_state
    manager = Tokra::StateManager.new
    state = Object.new
    manager.set(state)

    assert_same state, manager.get(Object)
  end

  def test_get_raises_if_not_found
    manager = Tokra::StateManager.new

    assert_raises(KeyError) { manager.get(Object) }
  end

  def test_try_get_returns_stored_state
    manager = Tokra::StateManager.new
    state = Object.new
    manager.set(state)

    assert_same state, manager.try_get(Object)
  end

  def test_try_get_returns_nil_if_not_found
    manager = Tokra::StateManager.new

    assert_nil manager.try_get(Object)
  end

  def test_stores_multiple_types
    manager = Tokra::StateManager.new
    string_state = "hello"
    array_state = [1, 2, 3]

    manager.set(string_state)
    manager.set(array_state)

    assert_same string_state, manager.get(String)
    assert_same array_state, manager.get(Array)
  end
end
