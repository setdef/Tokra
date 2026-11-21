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

    assert_equal Log::RotationStrategy::KeepOne.new, builder.__send__(:settings).rotation_strategy
    assert_equal Log::TimezoneStrategy::UseUtc.new, builder.__send__(:settings).timezone_strategy
    assert_equal 40_000, builder.__send__(:settings).max_file_size
    assert_equal :trace, builder.__send__(:settings).level
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
      -> { builder.skip_logger },
    ]

    calls.each { |call| assert_same builder, call.call }
  end

  def test_targets_replaces_and_target_adds
    first = stdout_target
    second = Log::Target.new(Log::TargetKind::Stderr.new)
    builder = Log::Builder.new.targets([first]).target(second)

    assert_equal [first, second], builder.__send__(:settings).targets
  end

  # The builder keeps its own list, as Rust's targets collects the
  # iterator it is given into a Vec of its own.
  def test_targets_keeps_its_own_list
    list = [stdout_target]
    builder = Log::Builder.new.targets(list)
    list << Log::Target.new(Log::TargetKind::Stderr.new)

    assert_equal 1, builder.__send__(:settings).targets.size
  end

  # Sizes above u64::MAX are clamped (lib.rs:459-466).
  def test_max_file_size_is_clamped_to_u64
    assert_equal (2 ** 64) - 1, Log::Builder.new.max_file_size(2 ** 70).__send__(:settings).max_file_size
  end

  # Tauri's build and split make a TauriPlugin named log
  # (lib.rs:666-711).
  def test_build_and_split_make_the_plugin_named_log
    plugin = Log::Builder.new.build
    split, = Log::Builder.new.clear_targets.split(app_handle)

    [plugin, split].each do |made|
      assert_instance_of Tokra::Plugin::TauriPlugin, made
      assert_equal "log", made.name
    end
  end

  # split returns the logger apart, and the lowest level it can log:
  # the builder's level, or Off with no targets, as fern's into_log
  # computes it (fern 0.7.1 builders.rs:589-595).
  def test_split_returns_the_level_and_the_logger_unattached
    _, max_level, logger = Log::Builder.new.level(:info).clear_targets.target(stdout_target).split(app_handle)
    _, none, = Log::Builder.new.level(:info).clear_targets.split(app_handle)

    assert_equal :info, max_level
    assert_equal :off, none
    assert_instance_of Log::Logger, logger
    refute_same logger, Log.logger, "split attaches nothing"
  end

  # skip_logger has split refuse, with Tauri's message (lib.rs:66-67,
  # 676-678).
  def test_split_after_skip_logger_raises_logger_not_initialized
    error = assert_raises(Log::Error::LoggerNotInitialized) { Log::Builder.new.skip_logger.split(app_handle) }

    assert_equal "Internal logger disabled and cannot be acquired or attached", error.message
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
end
