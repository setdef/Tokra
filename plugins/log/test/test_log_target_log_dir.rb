# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "tmpdir"
require "fileutils"

# Tests for LogDir target kind.
class TestLogTargetKindLogDir < Minitest::Test
  def make_stub_path_resolver(log_dir)
    resolver = Object.new
    resolver.define_singleton_method(:app_log_dir) { Pathname.new(log_dir) }
    resolver
  end

  def test_log_dir_with_file_name_is_data_class
    log_dir = Tokra::Plugins::Log::TargetKind::LogDir.new(file_name: "test")

    assert_kind_of Data, log_dir
    assert_equal "test", log_dir.file_name
  end

  def test_log_dir_defaults_file_name_to_nil
    log_dir = Tokra::Plugins::Log::TargetKind::LogDir.new

    assert_nil log_dir.file_name
  end

  def test_target_with_log_dir_creates_logger_in_temp_dir
    Dir.mktmpdir do |tmpdir|
      stub_path_resolver = make_stub_path_resolver(tmpdir)
      builder = Tokra::Plugins::Log::Builder.new
        .path_resolver(stub_path_resolver)

      kind = Tokra::Plugins::Log::TargetKind::LogDir.new(file_name: "test")
      target = Tokra::Plugins::Log::Target.new(kind)

      logger = target.to_logger(builder)
      logger.info("test message")

      log_file = Pathname.new(tmpdir).join("test.log")
      assert log_file.exist?, "Expected log file at #{log_file}"
      assert_includes log_file.read, "test message"
    end
  end

  def test_target_with_log_dir_creates_directory_if_missing
    Dir.mktmpdir do |tmpdir|
      nested_dir = Pathname.new(tmpdir).join("nested", "logs")
      stub_path_resolver = make_stub_path_resolver(nested_dir)
      builder = Tokra::Plugins::Log::Builder.new
        .path_resolver(stub_path_resolver)

      kind = Tokra::Plugins::Log::TargetKind::LogDir.new(file_name: "app")
      target = Tokra::Plugins::Log::Target.new(kind)

      target.to_logger(builder)

      assert nested_dir.exist?, "Expected directory #{nested_dir} to be created"
    end
  end

  def test_target_with_log_dir_uses_app_name_as_default_file_name
    Dir.mktmpdir do |tmpdir|
      stub_path_resolver = make_stub_path_resolver(tmpdir)
      builder = Tokra::Plugins::Log::Builder.new
        .path_resolver(stub_path_resolver)
        .app_name("myapp")

      kind = Tokra::Plugins::Log::TargetKind::LogDir.new
      target = Tokra::Plugins::Log::Target.new(kind)

      logger = target.to_logger(builder)
      logger.info("hello")

      log_file = Pathname.new(tmpdir).join("myapp.log")
      assert log_file.exist?, "Expected log file at #{log_file}"
    end
  end
end
