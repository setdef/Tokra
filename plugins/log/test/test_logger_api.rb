# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Ruby code logs through the Logger as Rust code logs through log's
# macros, with ::Logger's arguments, so the Logger can stand in for a
# ::Logger a library takes.
class TestLoggerApi < Minitest::Test
  include LogTest

  # The record's level and target, as a format sees them.
  LEVEL_AND_TARGET = Ractor.shareable_proc { |message, record| "#{record.level} #{record.target} #{message}" }

  private def records
    logged(Log::Builder.new.format(LEVEL_AND_TARGET)) { |log| yield log }.lines(chomp: true)
  end

  # Logger's FATAL and UNKNOWN are above log's highest level, Error.
  def test_each_method_logs_at_its_level
    lines = records do |log|
      log.trace("t")
      log.debug("d")
      log.info("i")
      log.warn("w")
      log.error("e")
      log.fatal("f")
      log.add(::Logger::UNKNOWN, "u")
      log.add(nil, "n")
    end

    assert_equal [
      "trace demo t",
      "debug demo d",
      "info demo i",
      "warn demo w",
      "error demo e",
      "error demo f",
      "error demo u",
      "error demo n",
], lines
  end

  # With a block, the argument is the progname, which becomes the target.
  def test_a_block_gives_the_message_and_the_argument_the_target
    assert_equal ["info db query"], records { |log| log.info("db") { "query" } }
  end

  def test_add_takes_a_severity_message_and_progname
    assert_equal ["warn net slow"], records { |log| log.add(::Logger::WARN, "slow", "net") }
  end

  def test_add_without_a_message_logs_the_progname
    assert_equal ["info demo just this"], records { |log| log.add(::Logger::INFO, nil, "just this") }
  end

  def test_trace_is_below_debug
    assert_equal ["trace demo t"], records { |log| log.add(Log::TRACE, "t") }
  end

  # Logger's msg2str: an exception logs its message, class, and backtrace,
  # anything else its inspect.
  def test_a_message_that_is_not_a_string_reads_as_logger_writes_it
    error = RuntimeError.new("boom")
    error.set_backtrace(["a.rb:1", "b.rb:2"])

    lines = records do |log|
      log.error(error)
      log.info(:ready)
    end

    assert_equal ["error demo boom (RuntimeError)", "a.rb:1", "b.rb:2", "info demo :ready"], lines
  end

  # Logger#add returns true whether or not it wrote.
  def test_add_returns_true
    logger = stdout_logger(Log::Builder.new.level(:off))

    assert logger.add(::Logger::INFO, "x")
  end
end
