# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Where each TargetKind writes (lib.rs:323-355, 587-657).
class TestTargets < Minitest::Test
  include LogTest

  # A native stand-in that puts the user's directories in +dir+, so the
  # real path resolver finds its log directory there.
  class Dirs
    def initialize(dir)
      @dir = dir
    end

    def home_dir = @dir
    def data_local_dir = @dir
  end

  # Tauri's DEFAULT_LOG_TARGETS (lib.rs:49-52).
  def test_the_default_targets_are_stdout_and_the_log_dir
    kinds = Log::Builder.new.configured_targets.map(&:kind)

    assert_equal [Log::TargetKind::Stdout.new, Log::TargetKind::LogDir.new], kinds
  end

  def test_stdout_and_stderr_write_each_line_with_a_newline
    plugin = Log::Builder.new.clear_format.clear_targets
      .target(Log::Target.new(Log::TargetKind::Stdout.new))
      .target(Log::Target.new(Log::TargetKind::Stderr.new))
      .build

    out, err = capture_io { plugin.info("both") }

    assert_equal ["both\n", "both\n"], [out, err]
  end

  # A Folder target writes <file_name>.log in its folder, creating it
  # (lib.rs:613-626).
  def test_a_folder_target_writes_its_file_creating_the_folder
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "nested", "logs")
      plugin = Log::Builder.new.clear_format.clear_targets
        .target(Log::Target.new(Log::TargetKind::Folder.new(path: folder, file_name: "events")))
        .build

      plugin.info("saved")

      assert_equal "saved\n", File.read(File.join(folder, "events.log"))
    end
  end

  # Without a file name a file is named for the app (lib.rs:620, 635).
  def test_a_folder_file_is_named_for_the_app_by_default
    Dir.mktmpdir do |dir|
      plugin = Log::Builder.new.app_name("Demo").clear_targets
        .target(Log::Target.new(Log::TargetKind::Folder.new(path: dir)))
        .build

      plugin.info("x")

      assert_path_exists File.join(dir, "Demo.log")
    end
  end

  # The LogDir target writes in the app's log directory, and names its
  # file after the package (lib.rs:627-641), both read from the handle as
  # Tauri reads app_handle.path() and package_info().name.
  def test_the_log_dir_target_writes_in_the_apps_log_directory
    Dir.mktmpdir do |dir|
      handle = app_handle
      resolver = Tokra::Path::Resolver.new(handle.config, native: Dirs.new(dir))
      plugin = Log::Builder.new.clear_format.app_handle(handle).path_resolver(resolver).clear_targets
        .target(Log::Target.new(Log::TargetKind::LogDir.new))
        .build

      plugin.info("to the log dir")

      file = resolver.app_log_dir.join("#{handle.package_info.name}.log")
      assert_equal "to the log dir\n", File.read(file)
    end
  end

  def test_the_log_dir_target_takes_a_file_name
    Dir.mktmpdir do |dir|
      handle = app_handle
      resolver = Tokra::Path::Resolver.new(handle.config, native: Dirs.new(dir))
      plugin = Log::Builder.new.app_handle(handle).path_resolver(resolver).clear_targets
        .target(Log::Target.new(Log::TargetKind::LogDir.new(file_name: "webview")))
        .build

      plugin.info("x")

      assert_path_exists resolver.app_log_dir.join("webview.log")
    end
  end

  # With only the app handle, the LogDir target asks the handle's own
  # path resolver for the directory.
  def test_the_log_dir_target_reads_the_handles_path_resolver
    Dir.mktmpdir do |dir|
      handle = app_handle
      resolver = Tokra::Path::Resolver.new(handle.config, native: Dirs.new(dir))
      handle.stub(:path, resolver) do
        Log::Builder.new.app_handle(handle).clear_targets.target(Log::Target.new(Log::TargetKind::LogDir.new))
          .build.info("x")
      end

      assert_path_exists resolver.app_log_dir.join("#{handle.package_info.name}.log")
    end
  end

  def test_the_log_dir_target_without_an_app_handle_raises
    error = assert_raises(ArgumentError) { Log::Builder.new.build }

    assert_equal "a LogDir target needs the app handle: call Builder#app_handle", error.message
  end

  # A record's target is the app's name when the call names none, as a
  # Rust record's is the module path, which starts with the app's crate.
  def test_a_ruby_record_is_targeted_at_the_app_by_default
    handle = app_handle
    out = logged(Log::Builder.new.app_handle(handle)) { |log| log.info("hi") }

    assert_includes out, "[#{handle.package_info.name}][INFO] hi"
  end

  # TargetKind::Dispatch hands each line to a Logger of the app's own, as
  # Tauri chains a fern::Dispatch (lib.rs:351-354, 656).
  def test_a_dispatch_target_hands_each_line_to_a_ruby_logger
    io = StringIO.new
    logger = ::Logger.new(io, formatter: -> (severity, _time, progname, message) { "#{severity} #{progname}: #{message}\n" })
    plugin = Log::Builder.new.clear_format.clear_targets
      .target(Log::Target.new(Log::TargetKind::Dispatch.new(logger)))
      .build

    plugin.trace("db") { "t" }
    plugin.info("db") { "i" }
    plugin.fatal("db") { "f" }

    assert_equal "DEBUG db: t\nINFO db: i\nERROR db: f\n", io.string
  end

  # A write that fails goes to standard error in fern's words
  # (fern 0.7.1 log_impl.rs:874-893), and logging goes on.
  def test_a_failed_write_reports_to_stderr
    plugin = Log::Builder.new.clear_format.clear_targets.target(stdout_target).build
    closed = StringIO.new
    closed.close

    _, err = capture_io do
      $stdout = closed
      plugin.info("lost")
    end

    assert_match(/\AError performing logging.\n\tattempted to log: lost\n\trecord: .+\n\tlogging error: not opened for writing\z/, err)
  end

  def test_an_unknown_target_kind_raises
    error = assert_raises(ArgumentError) { Log::Target.new($stdout) }

    assert_equal "unknown target kind: #{$stdout.inspect}", error.message
  end
end
