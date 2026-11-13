# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "tmpdir"
require "digest"
require "fileutils"

# The registration path the README and the Plugin RDoc show: build the
# plugin with Log::Builder and register it on the app handle from the setup
# hook. Runs a real Tokra::App with the window and event loop replaced.
class TestLogRegistration < Minitest::Test
  # Stands in for tao and wry: the loop delivers nothing but its end.
  module NoWindow
    # The user's local data directory: the temporary directory the test
    # runs the app in, so the window's webview keeps its data there.
    def self.data_local_dir = Dir.pwd

    class Proxy
      def respond(*) = nil
    end

    class EventLoop
      def initialize(_app_id) = nil
      def create_proxy = Proxy.new
      def run(callback) = callback.call(Tokra::Native::LoopDestroyedEvent.new)
    end

    class Window
      def self.empty(_proxy) = new
      def open(*) = nil
      def set_title(_title) = nil
      def set_size(_width, _height) = nil
    end

    class WebView
      def self.empty(_proxy) = new
      def open(*) = nil
      def eval(_script) = nil
    end

    # The real menu classes, which need no window (plan 042).
    Menu = Tokra::Native::Menu
    Submenu = Tokra::Native::Submenu
    MenuItem = Tokra::Native::MenuItem
    CheckMenuItem = Tokra::Native::CheckMenuItem
    PredefinedMenuItem = Tokra::Native::PredefinedMenuItem
    IconMenuItem = Tokra::Native::IconMenuItem
    MenuIcon = Tokra::Native::MenuIcon
  end

  def test_the_readme_example_registers_the_plugin_from_the_setup_hook
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        events = []
        # The README example, with the config written here and .run given
        # a native stand-in.
        File.write("tokra.conf.json", JSON.generate({ "identifier" => "com.tokra.log-readme" }))
        # The icons/icon.png beside the config that every app has, here
        # the core suite's.
        FileUtils.cp_r(File.expand_path("../../../test/fixtures/test_app/icons", __dir__), dir)
        built = Tokra::Builder.default
          .setup(&Ractor.shareable_proc { |app|
            log = Tokra::Plugins::Log::Builder.new
              .app_handle(app.handle)
              .level(:info)
              .targets([
                Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Stdout.new),
                Tokra::Plugins::Log::Target.new(Tokra::Plugins::Log::TargetKind::Folder.new(path: "logs")),
              ])
              .build
            app.handle.plugin(log)
            log.info("started")
          })
          .build(Tokra.generate_context(File.join(dir, "tokra.conf.json")), native: NoWindow)
        out, = capture_io { built.run { |_handle, event| events << event.class } }

        assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::Exit], events
        assert built.handle.remove_plugin("log"), "the setup hook should have registered the log plugin"
        name = built.handle.package_info.name
        assert_match(/\]\[#{Regexp.escape(name)}\]\[INFO\] started\n\z/, out)
        assert_match(/\]\[INFO\] started\n\z/, File.read(File.join(dir, "logs", "#{name}.log")))
      end
    end
  end

  def test_a_log_config_is_refused_as_tauris_unit_config_is
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tokra.conf.json"),
        JSON.generate({ "identifier" => "com.tokra.log-config", "plugins" => { "log" => { "level" => "info" } } }))
      FileUtils.cp_r(File.expand_path("../../../test/fixtures/test_app/icons", __dir__), dir)
      built = Tokra::Builder.default.plugin(Tokra::Plugins::Log::Builder.new.targets([]).build)
        .build(Tokra.generate_context(File.join(dir, "tokra.conf.json")), native: NoWindow)

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
