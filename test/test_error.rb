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

  # tauri::Error::PluginInitialization (error.rs:64-66), which plugin.rs:1009
  # builds from the plugin name and its setup error.
  def test_plugin_initialization_names_the_plugin_and_its_error
    error = Tokra::Error::PluginInitialization.new("global-shortcut", "Undefined error: 0 (os error 0)")

    assert_equal "failed to initialize plugin `global-shortcut`: Undefined error: 0 (os error 0)", error.message
    assert_equal "global-shortcut", error.plugin
    assert_kind_of Tokra::Error, error
  end

  # tauri::Error::InvalidArgs (error.rs:58-60): the command, the key, and
  # serde_json's error.
  def test_invalid_args_names_the_command_and_the_key
    error = Tokra::Error::InvalidArgs.new("register", "shortcuts", "invalid type: null, expected a sequence")

    assert_equal "invalid args `shortcuts` for command `register`: invalid type: null, expected a sequence", error.message
    assert_equal "register", error.command
    assert_equal "shortcuts", error.key
    assert_kind_of Tokra::Error, error
    refute_kind_of ArgumentError, error
  end
end
