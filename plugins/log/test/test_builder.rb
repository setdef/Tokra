# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Builder's defaults, its chaining, and the methods Tokra declines
# (lib.rs:395-565).
class TestBuilder < Minitest::Test
  include LogTest

  # Builder::default (lib.rs:404-431).
  def test_the_defaults_are_tauris
    builder = Log::Builder.new

    assert_equal Log::RotationStrategy::KeepOne.new, builder.configured_rotation_strategy
    assert_equal Log::TimezoneStrategy::UseUtc.new, builder.configured_timezone_strategy
    assert_equal 40_000, builder.configured_max_file_size
    assert_equal :trace, builder.configured_level
  end

  # Each setter returns the builder, as each Rust method returns Self.
  def test_each_setter_returns_the_builder
    builder = Log::Builder.new
    format = Ractor.shareable_proc { |message, _record| message }
    calls = [
      -> { builder.rotation_strategy(Log::RotationStrategy::KeepAll.new) },
      -> { builder.timezone_strategy(Log::TimezoneStrategy::UseLocal.new) },
      -> { builder.max_file_size(10) },
      -> { builder.clear_format },
      -> { builder.format(format) },
      -> { builder.level(:info) },
      -> { builder.filter(-> (_metadata) { true }) },
      -> { builder.clear_targets },
      -> { builder.target(stdout_target) },
      -> { builder.targets([stdout_target]) },
    ]

    calls.each { |call| assert_same builder, call.call }
  end

  def test_targets_replaces_and_target_adds
    first = stdout_target
    second = Log::Target.new(Log::TargetKind::Stderr.new)
    builder = Log::Builder.new.targets([first]).target(second)

    assert_equal [first, second], builder.configured_targets
  end

  # The builder keeps its own list, as Rust's targets collects the
  # iterator it is given into a Vec of its own.
  def test_targets_keeps_its_own_list
    list = [stdout_target]
    builder = Log::Builder.new.targets(list)
    list << Log::Target.new(Log::TargetKind::Stderr.new)

    assert_equal 1, builder.configured_targets.size
  end

  # Sizes above u64::MAX are clamped (lib.rs:459-466).
  def test_max_file_size_is_clamped_to_u64
    assert_equal (2 ** 64) - 1, Log::Builder.new.max_file_size(2 ** 70).configured_max_file_size
  end

  def test_build_returns_the_plugin_named_log
    plugin = stdout_plugin

    assert_instance_of Log::Plugin, plugin
    assert_equal "log", plugin.name
  end

  # Tauri filters by Rust module path (lib.rs:488-491), which Ruby records
  # do not carry.
  def test_level_for_is_declined
    error = assert_raises(NotImplementedError) { Log::Builder.new.level_for("hyper", :warn) }

    assert_match(/module path/, error.message)
    assert_match(/Builder#filter/, error.message)
  end

  # fern's colors feature (lib.rs:551-565).
  def test_with_colors_is_declined
    error = assert_raises(NotImplementedError) { Log::Builder.new.with_colors({}) }

    assert_match(/Builder#format/, error.message)
  end

  # Both exist to install or compose Rust's global logger
  # (lib.rs:519-533, 670-719), which Ruby lacks.
  def test_skip_logger_and_split_are_declined
    [-> { Log::Builder.new.skip_logger }, -> { Log::Builder.new.split(app_handle) }].each do |call|
      error = assert_raises(NotImplementedError) { call.call }

      assert_match(/global logger/, error.message)
      assert_match(/TargetKind::Dispatch/, error.message)
    end
  end
end
