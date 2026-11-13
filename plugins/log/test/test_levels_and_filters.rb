# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Which records pass: the builder's level and filters, then each target's
# filters, each filter seeing the record's metadata (lib.rs:376-383,
# 483-499; fern 0.7.1 Dispatch::shallow_enabled, log_impl.rs:493-503).
class TestLevelsAndFilters < Minitest::Test
  include LogTest

  # fern's Dispatch::new lets every level through until one is set.
  def test_every_level_passes_by_default
    out = logged(Log::Builder.new.clear_format) { |log| log.trace("lowest") }

    assert_equal "lowest\n", out
  end

  def test_a_level_drops_the_records_below_it
    out = logged(Log::Builder.new.clear_format.level(:info)) do |log|
      log.debug("dropped")
      log.info("kept")
      log.error("kept too")
    end

    assert_equal "kept\nkept too\n", out
  end

  # LevelFilter::Off lets nothing through.
  def test_off_drops_everything
    assert_empty(logged(Log::Builder.new.level(:off)) { |log| log.error("dropped") })
  end

  # Level filters parse as log's LevelFilter::from_str does: any case.
  def test_a_level_reads_any_case
    out = logged(Log::Builder.new.clear_format.level("WARN")) do |log|
      log.info("dropped")
      log.warn("kept")
    end

    assert_equal "kept\n", out
  end

  # log's ParseLevelError (log lib.rs:464-465).
  def test_an_unknown_level_raises_the_log_crates_error
    error = assert_raises(ArgumentError) { Log::Builder.new.level(:fatal) }

    assert_equal "attempted to convert a string that doesn't match an existing log level", error.message
  end

  # A level the record does not reach skips the block, as Logger does.
  def test_a_dropped_record_never_calls_its_block
    called = false
    logged(Log::Builder.new.level(:warn)) { |log| log.info { called = true } }

    refute called
  end

  # Builder::filter sees a Metadata of level and target.
  def test_a_builder_filter_sees_level_and_target
    seen = []
    filter = lambda do |metadata|
      seen << [metadata.class, metadata.level, metadata.target]
      true
    end
    logged(Log::Builder.new.filter(filter)) { |log| log.warn("db") { "slow" } }

    assert_equal [[Log::Metadata, :warn, "db"]], seen
  end

  # Every filter the builder holds has to pass (fern's filters.iter().all).
  def test_each_builder_filter_has_to_pass
    builder = Log::Builder.new.clear_format
      .filter(Ractor.shareable_proc { |metadata| metadata.level != :debug })
      .filter(Ractor.shareable_proc { |metadata| metadata.target != "noisy" })
    out = logged(builder) do |log|
      log.debug("dropped")
      log.info("noisy") { "dropped" }
      log.info("kept")
    end

    assert_equal "kept\n", out
  end

  # A target's filters choose what reaches that target alone, as in
  # Tauri's example that splits the webview's records into their own file.
  def test_a_target_filter_chooses_what_reaches_that_target
    webview = Ractor.shareable_proc { |metadata| metadata.target.start_with?(Log::WEBVIEW_TARGET) }
    ruby = Ractor.shareable_proc { |metadata| !metadata.target.start_with?(Log::WEBVIEW_TARGET) }
    plugin = Log::Builder.new.clear_format.clear_targets.targets([
      Log::Target.new(Log::TargetKind::Stdout.new).filter(webview),
      Log::Target.new(Log::TargetKind::Stderr.new).filter(ruby),
    ]).build

    out, err = capture_io do
      plugin.info("webview:main.js") { "from the page" }
      plugin.info("from Ruby")
    end

    assert_equal ["from the page\n", "from Ruby\n"], [out, err]
  end

  def test_filters_must_be_ractor_shareable
    error = assert_raises(Ractor::IsolationError) { stdout_target.filter(proc { true }) }
    assert_match(/filter/, error.message)

    error = assert_raises(Ractor::IsolationError) { stdout_target.format(proc { "" }) }
    assert_match(/format/, error.message)
  end
end
