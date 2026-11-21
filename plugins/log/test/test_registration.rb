# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "no_window"
require "digest"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

# The registration path the README and the Log RDoc show: build the plugin
# with Log::Builder and register it on the app's builder, as Tauri's is
# (lib.rs:691-708). Runs a real Tokra::App with the window and event loop
# replaced. This process attached its logger when the tests loaded
# (LogTest::FORWARDER), so an app here that attaches another fails as a
# second Tauri app would, and the README's own app runs in a process of
# its own.
class TestLogRegistration < Minitest::Test
  include LogTest

  # The README example, run in a fresh process with its config in the
  # directory it is given, followed by a second app, whose plugin cannot
  # attach a second logger. It prints the second app's error and the
  # level the first attached.
  README_APP = <<~RUBY
    require "pathname"
    require "tokra-log"
    require_relative #{File.expand_path('no_window', __dir__).dump}

    Dir.chdir(ARGV.fetch(0))
    config = File.join(Dir.pwd, "tokra.conf.json")
    log = Tokra::Plugins::Log::Builder.new
      .level(:info)
      .targets([
        Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Stdout.new),
        Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Folder.new(path: "logs")),
      ])
      .build
    Tokra::Builder.default.plugin(log).build(Tokra.generate_context(config), native: NoWindow).run
    Tokra::Plugins::Log.logger.info("started")

    second = Tokra::Builder.default.plugin(Tokra::Plugins::Log::Builder.new.clear_targets.build)
      .build(Tokra.generate_context(config), native: NoWindow)
    begin
      second.run
    rescue Tokra::Error::PluginInitialization => e
      puts e.message
    end
    puts Tokra::Plugins::Log.max_level
  RUBY

  # An app in +dir+ with +config+ over an identifier and the core suite's
  # icons/icon.png, which every app has beside its config.
  private def app_in(dir, config = {})
    File.write(File.join(dir, "tokra.conf.json"),
      JSON.generate({ "identifier" => "com.tokra.log-readme", "productName" => "demo" }.merge(config)))
    FileUtils.cp_r(File.expand_path("../../../test/fixtures/test_app/icons", __dir__), dir)
    File.join(dir, "tokra.conf.json")
  end

  # The plugin's setup attaches its logger as the process's logger,
  # where Log.logger finds it (lib.rs:691-708, 711-719), and a second
  # app's plugin then fails to initialize with the log crate's
  # SetLoggerError (log lib.rs:462-463).
  def test_the_readme_example_attaches_the_builders_logger
    Dir.mktmpdir do |dir|
      app_in(dir)
      out, status = Open3.capture2e(RbConfig.ruby, "-e", README_APP, dir)

      assert status.success?, out
      assert_match(/\]\[demo\]\[INFO\] started\n/, out)
      assert_match(/\]\[INFO\] started\n\z/, File.read(File.join(dir, "logs", "demo.log")))
      assert_includes out, "failed to initialize plugin `log`: attempted to set a logger after the logging " \
        "system was already initialized\n"
      assert out.end_with?("info\n"), out
    end
  end

  def test_the_plugin_registers_on_the_builder
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        events = []
        built = Tokra::Builder.default.plugin(Log::Builder.new.skip_logger.build)
          .build(Tokra.generate_context(app_in(dir)), native: NoWindow)
        built.run { |_handle, event| events << event.class }

        assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::Exit], events
        assert built.handle.remove_plugin("log"), "Builder#plugin should have registered the log plugin"
      end
    end
  end

  # This process attached LogTest::FORWARDER, so a plugin whose setup
  # attaches fails the app, and the process keeps its logger.
  def test_a_second_attach_fails_the_app_and_keeps_the_first_logger
    Dir.mktmpdir do |dir|
      built = Tokra::Builder.default.plugin(Log::Builder.new.clear_targets.build)
        .build(Tokra.generate_context(app_in(dir)), native: NoWindow)

      error = assert_raises(Tokra::Error::PluginInitialization) { built.run }

      assert_equal "failed to initialize plugin `log`: attempted to set a logger after the logging system was " \
        "already initialized", error.message
      assert_same FORWARDER, Log.logger
    end
  end

  # The setup makes the logger from the builder as it was at #build, as
  # Tauri's build consumes the builder: the folder is made though the
  # builder lost its target, before the attach fails.
  def test_the_setup_uses_the_builder_as_it_was_at_build
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "made")
      builder = Log::Builder.new.clear_targets.target(Log::Target.new(Log::TargetKind::Folder.new(path: folder)))
      plugin = builder.build
      builder.clear_targets
      built = Tokra::Builder.default.plugin(plugin).build(Tokra.generate_context(app_in(dir)), native: NoWindow)

      assert_raises(Tokra::Error::PluginInitialization) { built.run }
      assert_path_exists File.join(folder, "demo.log")
      refute open_file?(File.join(folder, "demo.log")), "attach_logger drops the logger it refuses"
    end
  end

  # When a target fails, the setup drops the outputs it opened before
  # it, as Rust drops the dispatch it was building (lib.rs:576-662).
  def test_a_failed_target_closes_the_files_opened_before_it
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "taken"), "")
      first = Log::Target.new(Log::TargetKind::Folder.new(path: File.join(dir, "first")))
      second = Log::Target.new(Log::TargetKind::Folder.new(path: File.join(dir, "taken")))
      built = Tokra::Builder.default.plugin(Log::Builder.new.clear_targets.targets([first, second]).build)
        .build(Tokra.generate_context(app_in(dir)), native: NoWindow)

      assert_raises(Tokra::Error::PluginInitialization) { built.run }
      refute open_file?(File.join(dir, "first", "demo.log"))
    end
  end

  def test_attach_logger_refuses_a_second_logger
    error = assert_raises(Log::SetLoggerError) { Log.attach_logger(:info, stdout_logger) }

    assert_equal "attempted to set a logger after the logging system was already initialized", error.message
    assert_same FORWARDER, Log.logger
    assert_equal :trace, Log.max_level
  end

  # A folder the setup cannot create fails the app, as Tauri's
  # create_dir_all error does (lib.rs:613-616).
  def test_a_folder_that_cannot_be_made_fails_the_app
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "taken"), "")
      folder = Log::Target.new(Log::TargetKind::Folder.new(path: File.join(dir, "taken")))
      built = Tokra::Builder.default.plugin(Log::Builder.new.clear_targets.target(folder).build)
        .build(Tokra.generate_context(app_in(dir)), native: NoWindow)

      error = assert_raises(Tokra::Error::PluginInitialization) { built.run }

      assert_match(/\Afailed to initialize plugin `log`: File exists/, error.message)
    end
  end

  def test_a_log_config_is_refused_as_tauris_unit_config_is
    Dir.mktmpdir do |dir|
      built = Tokra::Builder.default.plugin(Log::Builder.new.skip_logger.build)
        .build(Tokra.generate_context(app_in(dir, "plugins" => { "log" => { "level" => "info" } })), native: NoWindow)

      error = assert_raises(Tokra::Error::PluginInitialization) { built.run }

      assert_equal "failed to initialize plugin `log`: Error deserializing 'plugins.log' within your Tokra " \
        "configuration: invalid type: map, expected unit", error.message
    end
  end

  # SHA-256 of plugins/log/api-iife.js at plugins-workspace d4613ff0.
  UPSTREAM_API_SCRIPT_SHA256 = "447a5072363e1b8d4ca171e32d5c2ffbf743efb018be21b8a0b27f50aac13c9f"

  def test_the_gem_names_tauris_global_api_script
    path = File.expand_path("../lib/tokra/plugins/log/api-iife.js", __dir__)

    assert_includes Tokra::Utils::Plugin.global_api_script_paths, File.realpath(path)
    assert_equal UPSTREAM_API_SCRIPT_SHA256, Digest::SHA256.file(path).hexdigest, "upstream's file, unchanged"
  end
end
