# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::ResourceTable.
class TestResourceTable < Minitest::Test
  # Helper class that implements the Resource interface for testing.
  class TestResource
    include Tokra::Resource

    attr_reader :value
    attr_accessor :closed

    def initialize(value = nil)
      @value = value
      @closed = false
    end

    def close
      @closed = true
      nil
    end
  end

  def test_new_creates_instance
    table = Tokra::ResourceTable.new
    assert_instance_of Tokra::ResourceTable, table
  end

  def test_has_returns_false_for_unknown_rid
    table = Tokra::ResourceTable.new
    refute table.has?(42)
  end

  def test_add_returns_integer_id
    table = Tokra::ResourceTable.new
    rid = table.add(TestResource.new)
    assert_kind_of Integer, rid, "add should return an integer resource ID"
  end

  def test_has_returns_true_after_add
    table = Tokra::ResourceTable.new
    rid = table.add(TestResource.new)
    assert table.has?(rid), "has? should return true for added resource"
  end

  def test_get_returns_stored_resource
    table = Tokra::ResourceTable.new
    resource = TestResource.new
    rid = table.add(resource)
    assert_same resource, table.get(rid), "get should return the same resource object"
  end

  def test_get_raises_bad_resource_id_for_unknown
    table = Tokra::ResourceTable.new
    error = assert_raises(Tokra::Error::BadResourceId) { table.get(999) }
    assert_equal 999, error.rid, "error should contain the bad rid"
  end

  def test_take_removes_and_returns_resource
    table = Tokra::ResourceTable.new
    resource = Object.new
    rid = table.add(resource)

    taken = table.take(rid)

    assert_same resource, taken, "take should return the resource"
    refute table.has?(rid), "take should remove the resource from the table"
  end

  def test_take_does_not_call_close
    table = Tokra::ResourceTable.new
    resource = Minitest::Mock.new
    rid = table.add(resource)

    # If close were called, the mock would fail verification
    table.take(rid)

    resource.verify
  end

  def test_close_removes_resource_and_calls_close
    table = Tokra::ResourceTable.new
    resource = Minitest::Mock.new
    resource.expect(:close, nil)
    rid = table.add(resource)

    table.close(rid)

    refute table.has?(rid), "close should remove the resource from the table"
    resource.verify
  end

  def test_close_works_with_resource_module
    table = Tokra::ResourceTable.new
    resource = TestResource.new
    rid = table.add(resource)

    table.close(rid)

    refute table.has?(rid), "close should remove the resource"
    assert resource.closed, "close should call resource.close"
  end

  def test_replace_updates_resource
    table = Tokra::ResourceTable.new
    rid = table.add(TestResource.new("original"))

    replacement = TestResource.new("replacement")
    table.replace(rid, replacement)

    assert_equal "replacement", table.get(rid).value, "replace should update the stored resource"
  end

  def test_replace_raises_bad_resource_id_for_unknown
    table = Tokra::ResourceTable.new
    assert_raises(Tokra::Error::BadResourceId) { table.replace(999, TestResource.new) }
  end

  def test_clear_removes_all_resources
    table = Tokra::ResourceTable.new
    rid1 = table.add(TestResource.new)
    rid2 = table.add(TestResource.new)

    table.clear

    refute table.has?(rid1), "clear should remove first resource"
    refute table.has?(rid2), "clear should remove second resource"
  end

  def test_names_yields_id_and_name_pairs
    table = Tokra::ResourceTable.new
    resource = Minitest::Mock.new
    resource.expect(:name, "TestResource")
    rid = table.add(resource)

    pairs = table.names.to_a

    assert_equal 1, pairs.size
    assert_equal [rid, "TestResource"], pairs.first
    resource.verify
  end

  def test_names_uses_default_resource_name
    table = Tokra::ResourceTable.new
    resource = TestResource.new
    rid = table.add(resource)

    pairs = table.names.to_a

    assert_equal 1, pairs.size
    assert_equal rid, pairs.first[0]
    assert_match(/TestResource/, pairs.first[1])
  end

  def test_names_returns_enumerator_without_block
    table = Tokra::ResourceTable.new
    table.add(TestResource.new)

    enum = table.names

    assert_instance_of Enumerator, enum
    assert_equal 1, enum.count
  end
end
