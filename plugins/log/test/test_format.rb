# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# How a line is formatted: the builder's format once, then each target's
# format on the formatted line, as fern's dispatches chain (lib.rs:404-481,
# 583-585; fern 0.7.1 log_impl.rs:446-550).
class TestFormat < Minitest::Test
  include LogTest

  # The default format: UTC date and time, target, level, message
  # (lib.rs:404-421, DEFAULT_TIMEZONE_STRATEGY at lib.rs:48).
  def test_the_default_line_is_utc_time_target_level_and_message
    out = nil
    stamps = stamps_around(Log::TimezoneStrategy::UseUtc.new) do
      out = logged(Log::Builder.new.app_name("demo")) { |log| log.info("hello") }
    end

    assert_match(/\A#{STAMP}\[demo\]\[INFO\] hello\n\z/o, out)
    assert_includes stamps, out[0, 22]
  end

  # log::Level's Display names each level in capitals (log lib.rs:460).
  def test_each_level_is_named_as_the_log_crate_names_it
    out = logged(Log::Builder.new.app_name("demo")) do |log|
      log.trace("t")
      log.debug("d")
      log.info("i")
      log.warn("w")
      log.error("e")
    end

    assert_equal %w[TRACE DEBUG INFO WARN ERROR], out.scan(/\]\[([A-Z]+)\] /).flatten
  end

  # Builder::timezone_strategy replaces the format with one that puts the
  # level before the target, in the strategy's time (lib.rs:443-457).
  def test_a_timezone_strategy_formats_level_before_target_in_its_time
    local = Log::TimezoneStrategy::UseLocal.new
    out = nil
    stamps = stamps_around(local) do
      out = logged(Log::Builder.new.app_name("demo").timezone_strategy(local)) { |log| log.warn("careful") }
    end

    assert_match(/\A#{STAMP}\[WARN\]\[demo\] careful\n\z/o, out)
    assert_includes stamps, out[0, 22]
  end

  # Both set the dispatch's one format, so the later call wins.
  def test_format_after_timezone_strategy_replaces_it
    builder = Log::Builder.new
      .timezone_strategy(Log::TimezoneStrategy::UseLocal.new)
      .format(Ractor.shareable_proc { |message, record| "#{record.level}:#{message}" })

    assert_equal "info:hi\n", logged(builder) { |log| log.info("hi") }
  end

  def test_timezone_strategy_after_format_replaces_it
    builder = Log::Builder.new.app_name("demo")
      .format(Ractor.shareable_proc { |message, _record| "custom #{message}" })
      .timezone_strategy(Log::TimezoneStrategy::UseUtc.new)

    assert_match(/\A#{STAMP}\[INFO\]\[demo\] hi\n\z/o, logged(builder) { |log| log.info("hi") })
  end

  # Builder::clear_format leaves the message alone (lib.rs:468-473).
  def test_clear_format_writes_the_message_alone
    assert_equal "plain\n", logged(Log::Builder.new.clear_format) { |log| log.info("plain") }
  end

  # A format receives the message and the record, and returns the line.
  def test_a_format_receives_the_message_and_the_record
    format = Ractor.shareable_proc do |message, record|
      "#{record.level}|#{record.target}|#{record.args}|#{message}"
    end
    builder = Log::Builder.new.format(format)

    assert_equal "warn|net|ping|ping\n", logged(builder) { |log| log.warn("net") { "ping" } }
  end

  # A format that gives nothing back leaves the record as it was, as fern
  # finishes a record whose format never called finish (log_impl.rs:452-472).
  def test_a_format_that_returns_nil_leaves_the_message_unformatted
    builder = Log::Builder.new.format(Ractor.shareable_proc { |_message, _record| nil })

    assert_equal "as is\n", logged(builder) { |log| log.info("as is") }
  end

  # A target's format formats the line the builder's format already made
  # (lib.rs:583-585; fern's FormatCallback::finish, log_impl.rs:531-550).
  def test_a_target_format_wraps_the_formatted_line
    target = stdout_target.format(Ractor.shareable_proc { |message, record| "<#{message}|#{record.args}>" })
    plugin = Log::Builder.new.clear_format.format(Ractor.shareable_proc { |message, _record| "[#{message}]" })
      .clear_targets.target(target).build

    out, = capture_io { plugin.info("x") }

    assert_equal "<[x]|[x]>\n", out
  end

  # Each target formats on its own; one target's format reaches no other.
  def test_one_targets_format_leaves_the_others_alone
    plain = Log::Target.new(Log::TargetKind::Stdout.new)
    loud = Log::Target.new(Log::TargetKind::Stderr.new).format(Ractor.shareable_proc { |message, _| message.upcase })
    plugin = Log::Builder.new.clear_format.clear_targets.targets([plain, loud]).build

    out, err = capture_io { plugin.info("quiet") }

    assert_equal ["quiet\n", "QUIET\n"], [out, err]
  end
end
