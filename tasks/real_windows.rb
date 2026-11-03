# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# Which tests open real windows, and where they run (Plan 056).
#
# A real-window test opens tao windows, menus, trays, file panels, or
# notifications. On the maintainer's Mac those run in the hidden
# +tokratest+ session (HiddenJob), so none opens in the maintainer's own;
# on CI and off macOS they run here, as always.
module RealWindows
  # The tests that take the keyboard and mouse on macOS, which run first.
  KEYBOARD = "test/integration/keyboard/**/*_test.rb"

  # Every test file here launches a RealApp fixture, or is beside them.
  INTEGRATION = "test/integration/"

  # The in-process native tests share NativeEventLoop, and the fixture
  # tests, plugins' included, launch through RealApp.
  MARKER = /\b(?:RealApp|NativeEventLoop)(?:\.|::)/

  # Plugin tests that open real system UI without either: AppKit's file
  # panels, and the notification center's banners.
  NAMED = %w[
    plugins/dialog/test/test_macos_dialogs.rb
    plugins/notification/test/test_macos_notifications.rb
  ].freeze

  # The repository, which the paths here are relative to.
  ROOT = File.expand_path("..", __dir__)

  # What the real-window tasks set for their test processes, which the
  # tests' tripwire reads.
  RUN = "TOKRA_REAL_WINDOWS_RUN"

  # The values TOKRA_REAL_WINDOWS takes.
  PLACES = { "local" => :local, "hidden" => :hidden }.freeze

  class << self
    # Where the real-window tests run: +:local+ (this session) or
    # +:hidden+ (tokratest's). TOKRA_REAL_WINDOWS says so when set; else
    # they run here on CI (CI=true, as GitHub sets it) and off macOS, and
    # hidden on a Mac.
    def where(env = ENV, host_os = RbConfig::CONFIG["host_os"])
      chosen = env["TOKRA_REAL_WINDOWS"].to_s
      unless chosen.empty?
        return PLACES.fetch(chosen) do
          raise ArgumentError, "TOKRA_REAL_WINDOWS is local or hidden, not #{chosen.inspect}"
        end
      end
      return :local if env["CI"] == "true" || !host_os.include?("darwin")

      :hidden
    end

    # The environment for a test process: TOKRA_REAL_WINDOWS_RUN=1 lets it
    # open real windows (test/support/real_windows_run.rb) if +windows+,
    # and is unset otherwise, whatever the shell exported.
    def run_env(windows) = { RUN => (windows ? "1" : nil) }

    # Whether the test file at +path+ (relative to the repository) opens
    # real windows. +source+ is its text.
    def test_file?(path, source = File.read(File.join(ROOT, path)))
      path.start_with?(INTEGRATION) || NAMED.include?(path) || source.match?(MARKER)
    end

    # The test files among +paths+ that open real windows, and the rest.
    def split(paths)
      paths.partition { |path| test_file?(path) }
    end

    # +plugin+'s test files (relative to it), those that open real windows
    # if +windows+, else the rest, as its Rakefile's pattern finds them.
    def plugin_tests(plugin, windows:)
      Dir.glob("#{plugin}/test/**/test_*.rb", base: ROOT).sort
        .select { |path| test_file?(path) == windows }
        .map { |path| path.delete_prefix("#{plugin}/") }
    end
  end
end
