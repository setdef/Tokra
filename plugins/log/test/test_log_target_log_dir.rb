# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "tokra-log"
require "tmpdir"
require "pathname"

# Tests for LogDir target kind (Tauri parity).
class TestLogTargetKindLogDir < Minitest::Test
  def test_log_dir_target_kind_exists
    target_kind = Tokra::Plugins::Log::TargetKind::LogDir.new

    assert_kind_of Tokra::Plugins::Log::TargetKind::LogDir, target_kind
  end

  def test_log_dir_accepts_file_name
    target_kind = Tokra::Plugins::Log::TargetKind::LogDir.new(file_name: "custom")

    assert_equal "custom", target_kind.file_name
  end

  def test_log_dir_file_name_defaults_to_nil
    target_kind = Tokra::Plugins::Log::TargetKind::LogDir.new

    assert_nil target_kind.file_name
  end

  def test_target_with_log_dir_creates_logger_in_temp_dir
    Dir.mktmpdir do |tmpdir|
      stub_path_resolver = make_stub_path_resolver(tmpdir)

      kind = Tokra::Plugins::Log::TargetKind::LogDir.new(file_name: "test")
      target = Tokra::Plugins::Log::Target.new(kind)

      logger = target.to_logger(path_resolver: stub_path_resolver)
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

      kind = Tokra::Plugins::Log::TargetKind::LogDir.new(file_name: "app")
      target = Tokra::Plugins::Log::Target.new(kind)

      target.to_logger(path_resolver: stub_path_resolver)

      assert nested_dir.exist?, "Expected directory #{nested_dir} to be created"
    end
  end

  def test_target_with_log_dir_uses_app_name_as_default_file_name
    Dir.mktmpdir do |tmpdir|
      stub_path_resolver = make_stub_path_resolver(tmpdir)

      kind = Tokra::Plugins::Log::TargetKind::LogDir.new
      target = Tokra::Plugins::Log::Target.new(kind)

      logger = target.to_logger(path_resolver: stub_path_resolver, app_name: "myapp")
      logger.info("hello")

      log_file = Pathname.new(tmpdir).join("myapp.log")
      assert log_file.exist?, "Expected log file at #{log_file}"
    end
  end

  private def make_stub_path_resolver(dir)
    stub = Object.new
    stub.define_singleton_method(:app_log_dir) { Pathname.new(dir) }
    stub
  end
end
