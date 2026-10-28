# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "tmpdir"

# The registration path the README and the Plugin RDoc show: build the
# plugin with Log::Builder and register it on the app handle from the setup
# hook. Runs a real Tokra::App with the window and event loop replaced.
class TestLogRegistration < Minitest::Test
  # Stands in for tao and wry: the loop delivers nothing but its end.
  module NoWindow
    class Proxy
      def respond(*) = nil
    end

    class EventLoop
      def create_proxy = Proxy.new
      def run(callback) = callback.call(Tokra::Native::LoopDestroyedEvent.new)
    end

    class Window
      def initialize(_event_loop) = nil
      def set_title(_title) = nil
      def set_size(_width, _height) = nil
    end

    class WebView
      def self.new_with_protocol(*) = new
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
        # The README example, with .run given a native stand-in.
        built = Tokra::Builder.default
          .setup(&Ractor.shareable_proc { |app|
            log = Tokra::Plugins::Log::Builder.new
              .level(:info)
              .targets([Tokra::Plugins::Log::Target.new(Pathname("app.log"))])
              .build
            app.handle.plugin(log)
          })
          .build(native: NoWindow)
        built.run { |_handle, event| events << event.class }

        assert_equal [Tokra::RunEvent::Ready, Tokra::RunEvent::Exit], events
        assert built.handle.remove_plugin("log"), "the setup hook should have registered the log plugin"
        assert_path_exists File.join(dir, "app.log")
      end
    end
  end
end
