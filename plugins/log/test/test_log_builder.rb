# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "stringio"

# Tests for Builder fluent API (Tauri parity).
class TestLogBuilder < Minitest::Test
  def test_builder_new_returns_builder
    skip "TODO: Builder not implemented"
  end

  def test_builder_level_sets_global_level
    skip "TODO: Builder not implemented"
  end

  def test_builder_level_for_sets_per_module_level
    skip "TODO: Builder#level_for not implemented"
  end

  def test_builder_target_adds_target
    skip "TODO: Builder not implemented"
  end

  def test_builder_targets_replaces_all_targets
    skip "TODO: Builder not implemented"
  end

  def test_builder_clear_targets_removes_all
    skip "TODO: Builder#clear_targets not implemented"
  end

  def test_builder_format_sets_custom_formatter
    skip "TODO: Builder#format not implemented"
  end

  def test_builder_filter_adds_global_filter
    skip "TODO: Builder#filter not implemented"
  end

  def test_builder_rotation_strategy_sets_strategy
    skip "TODO: Builder#rotation_strategy not implemented"
  end

  def test_builder_timezone_strategy_sets_timezone
    skip "TODO: Builder#timezone_strategy not implemented"
  end

  def test_builder_max_file_size_sets_size
    skip "TODO: Builder#max_file_size not implemented"
  end

  def test_builder_build_returns_plugin
    skip "TODO: Builder not implemented"
  end
end
