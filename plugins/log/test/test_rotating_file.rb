# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# The log file of a Folder or LogDir target: a port of Tauri's
# RotatingFile (lib.rs:149-315), in real files in a temporary directory.
class TestRotatingFile < Minitest::Test
  include LogTest

  # A timezone strategy whose clock stands still, so archive names are
  # known in advance.
  class StoppedClock < Data.define(:now)
    def get_now = now
  end

  NOW = Ferro::Time::OffsetDateTime.from(Time.utc(2026, 11, 13, 9, 41, 7))
  ARCHIVE = "app_2026-11-13_09-41-07.log"

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  private def rotating(max_size, strategy, file_name: "app")
    Log::RotatingFile.new(@dir, file_name, max_size, strategy, StoppedClock.new(NOW))
  end

  private def line(file, text)
    file.write(text)
    file.flush
  end

  private def read(name)
    File.read(File.join(@dir, name))
  end

  private def files
    Dir.children(@dir).sort
  end

  # Write buffers and flush writes, as fern's writer output calls them.
  def test_a_write_reaches_the_file_on_flush
    file = rotating(100, Log::RotationStrategy::KeepOne.new)
    file.write("buffered\n")

    assert_equal "", read("app.log")
    file.flush
    assert_equal "buffered\n", read("app.log")
  end

  # The file is rotated before a write that would take it past the
  # maximum (lib.rs:302-305); KeepOne deletes the old one (lib.rs:221-223).
  def test_keep_one_starts_over_when_a_write_would_pass_the_maximum
    file = rotating(10, Log::RotationStrategy::KeepOne.new)
    line(file, "12345\n")
    line(file, "6789\n")

    assert_equal ["app.log"], files
    assert_equal "6789\n", read("app.log")
  end

  # A write that just reaches the maximum stays.
  def test_a_write_that_reaches_the_maximum_exactly_stays
    file = rotating(11, Log::RotationStrategy::KeepOne.new)
    line(file, "12345\n")
    line(file, "6789\n")

    assert_equal "12345\n6789\n", read("app.log")
  end

  # An empty file takes a line longer than the maximum (current_size != 0).
  def test_an_empty_file_takes_a_line_longer_than_the_maximum
    file = rotating(4, Log::RotationStrategy::KeepAll.new)
    line(file, "a long line\n")

    assert_equal ["app.log"], files
    assert_equal "a long line\n", read("app.log")
  end

  # KeepAll renames the old file with the date in LOG_DATE_FORMAT
  # (lib.rs:53-54, 212-214, 264-285).
  def test_keep_all_renames_the_old_file_with_its_date
    file = rotating(10, Log::RotationStrategy::KeepAll.new)
    line(file, "12345\n")
    line(file, "6789\n")

    assert_equal ["app.log", ARCHIVE], files
    assert_equal "12345\n", read(ARCHIVE)
    assert_equal "6789\n", read("app.log")
  end

  # An archive already at the name moves aside to .bak (lib.rs:273-282).
  def test_an_archive_already_at_the_name_moves_to_bak
    File.write(File.join(@dir, ARCHIVE), "older\n")
    file = rotating(10, Log::RotationStrategy::KeepAll.new)
    line(file, "12345\n")
    line(file, "6789\n")

    assert_equal "older\n", read("#{ARCHIVE}.bak")
    assert_equal "12345\n", read(ARCHIVE)
  end

  # Opening a file already at the maximum rotates it (lib.rs:186-188).
  def test_a_full_file_rotates_when_opened
    File.write(File.join(@dir, "app.log"), "1234567890")
    rotating(10, Log::RotationStrategy::KeepAll.new)

    assert_equal "1234567890", read(ARCHIVE)
    assert_equal "", read("app.log")
  end

  # KeepSome trims the archives when the file opens (lib.rs:189-191) and
  # leaves room for the one it is about to make when it rotates
  # (lib.rs:215-220); the oldest go first (lib.rs:232-262).
  def test_keep_some_keeps_that_many_archives
    %w[2026-01-01_00-00-00 2026-02-01_00-00-00 2026-03-01_00-00-00].each do |date|
      File.write(File.join(@dir, "app_#{date}.log"), date)
    end
    file = rotating(10, Log::RotationStrategy::KeepSome.new(2))

    assert_equal %w[app.log app_2026-02-01_00-00-00.log app_2026-03-01_00-00-00.log], files

    line(file, "12345\n")
    line(file, "6789\n")

    assert_equal ["app.log", "app_2026-03-01_00-00-00.log", ARCHIVE], files
  end

  # Only <file_name>_<date>.log counts as an archive.
  def test_keep_some_leaves_other_files_alone
    %w[app.log.bak other_2026.log app-2026.log app.old.log app_2026-01-01_00-00-00.log.bak].each do |name|
      File.write(File.join(@dir, name), name)
    end
    rotating(10, Log::RotationStrategy::KeepSome.new(1))

    assert_equal %w[app-2026.log app.log app.log.bak app.old.log app_2026-01-01_00-00-00.log.bak other_2026.log], files
  end

  # Rust's Path::with_extension replaces the name's own extension.
  def test_the_file_name_takes_log_in_place_of_its_extension
    line(rotating(100, Log::RotationStrategy::KeepOne.new, file_name: "app.v2"), "x\n")

    assert_equal ["app.log"], files
  end

  # Through the logger, archives are named in the builder's timezone,
  # UTC by default (lib.rs:48).
  def test_the_logger_names_archives_in_utc_by_default
    logger = logger_of(Log::Builder.new.max_file_size(1)
      .rotation_strategy(Log::RotationStrategy::KeepAll.new)
      .clear_targets.target(Log::Target.new(Log::TargetKind::Folder.new(path: @dir))), app_handle(product_name: "app"))
    before = Ferro::Time::OffsetDateTime.now_utc.format(Log::LOG_DATE_FORMAT)
    logger.info("first")
    logger.info("second")
    after = Ferro::Time::OffsetDateTime.now_utc.format(Log::LOG_DATE_FORMAT)

    archive = files.find { |name| name != "app.log" }
    assert_includes [before, after], archive[/\Aapp_(.+)\.log\z/, 1]
  end

  # Tauri rotates at 40000 bytes with KeepOne unless told otherwise
  # (lib.rs:46-47).
  def test_the_logger_rotates_at_forty_thousand_bytes_keeping_one
    logger = logger_of(Log::Builder.new.clear_format
      .clear_targets.target(Log::Target.new(Log::TargetKind::Folder.new(path: @dir))), app_handle(product_name: "app"))
    logger.info("a" * 39_998)
    logger.info("b")

    assert_equal ["app.log"], files
    assert_equal "b\n", read("app.log")
  end
end
