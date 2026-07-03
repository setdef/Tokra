# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Error and nested error classes.
class TestError < Minitest::Test
  def test_bad_resource_id_stores_rid
    error = Tokra::Error::BadResourceId.new(42)
    assert_equal 42, error.rid, "BadResourceId should store the rid that was not found"
  end

  def test_bad_resource_id_message_matches_tauri
    error = Tokra::Error::BadResourceId.new(999)
    assert_equal "The resource id 999 is invalid.", error.message,
      "Error message must match tauri::Error::BadResourceId (error.rs)"
  end

  def test_bad_resource_id_is_tokra_error
    error = Tokra::Error::BadResourceId.new(1)
    assert_kind_of Tokra::Error, error, "BadResourceId should inherit from Tokra::Error"
  end
end
