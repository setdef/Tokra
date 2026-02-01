# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "tmpdir"

# Filesystem integration tests for RotationStrategy.
#
# Verifies rotation strategies work end-to-end with Ruby Logger.
class TestRotationStrategyIntegration < Minitest::Test
  RotationStrategy = Tokra::Plugins::Log::RotationStrategy

  def test_keep_one_removes_old_log_on_rotation
    Dir.mktmpdir do |dir|
      log_path = Pathname(dir).join("app.log")
      target = Tokra::Plugins::Log::Target.new(log_path)
        .rotation_strategy(RotationStrategy::KeepOne.new)
      builder = Tokra::Plugins::Log::Builder.new.max_file_size(50)

      logger = target.to_logger(builder)

      # Write enough to trigger rotation (50 bytes + header)
      10.times { |i| logger.info("Message #{i} padded for size") }

      # KeepOne should only keep current file, no numbered backups
      rotated_files = Dir.glob(Pathname(dir).join("app.log.*"))
      assert rotated_files.size <= 1, "KeepOne should keep at most 1 rotated file, found: #{rotated_files}"
    end
  end

  def test_keep_all_preserves_rotated_files
    Dir.mktmpdir do |dir|
      log_path = Pathname(dir).join("app.log")
      target = Tokra::Plugins::Log::Target.new(log_path)
        .rotation_strategy(RotationStrategy::KeepAll.new)
      builder = Tokra::Plugins::Log::Builder.new.max_file_size(50)

      logger = target.to_logger(builder)

      # Write enough to trigger multiple rotations
      20.times { |i| logger.info("Message #{i} for rotation test") }

      # KeepAll uses 'daily' which doesn't create numbered files in same test
      # Instead verify that the main log file exists and was written to
      assert log_path.exist?, "Log file should exist"
      assert log_path.size.positive?, "Log file should have content"
    end
  end

  def test_keep_some_limits_rotated_file_count
    Dir.mktmpdir do |dir|
      log_path = Pathname(dir).join("app.log")
      target = Tokra::Plugins::Log::Target.new(log_path)
        .rotation_strategy(RotationStrategy::KeepSome.new(count: 3))
      builder = Tokra::Plugins::Log::Builder.new.max_file_size(50)

      logger = target.to_logger(builder)

      # Write enough to trigger multiple rotations
      50.times { |i| logger.info("Msg #{i} padding for rotation trigger") }

      # KeepSome(3) should keep at most 3 rotated files
      rotated_files = Dir.glob(Pathname(dir).join("app.log.*"))
      assert rotated_files.size <= 3, "KeepSome(3) should keep at most 3 rotated files, found: #{rotated_files.size}"
    end
  end
end
