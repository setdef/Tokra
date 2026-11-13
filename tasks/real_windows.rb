# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Which tests open real windows (Plans 056, 057, and 061).
#
# A real-window test opens tao windows, menus, trays, file panels, or
# notifications, or uses the session's clipboard. They run apart from the
# rest, in test:gui, in the session that runs the gate, so test:core and
# plugins:test open nothing. The few CONSOLE names run only in
# test:console, once, inside its spoken span.
module RealWindows
  # The tests that take the keyboard and mouse on macOS, which run first.
  KEYBOARD = "test/integration/keyboard/**/*_test.rb"

  # Every test file here launches a RealApp fixture, or is beside them.
  INTEGRATION = "test/integration/"

  # The in-process native tests share NativeEventLoop, and the fixture
  # tests, plugins' included, launch through RealApp.
  MARKER = /\b(?:RealApp|NativeEventLoop)(?:\.|::)/

  # Plugin tests that open real system UI, or use the session's own, without
  # either: AppKit's file panels, the notification center's banners,
  # Windows' toasts, the system clipboard, and hotkeys registered for the
  # whole desktop (on Linux, the suite's private Xvfb's).
  NAMED = %w[
    plugins/clipboard/test/test_clipboard.rb
    plugins/dialog/test/test_macos_dialogs.rb
    plugins/global-shortcut/test/test_commands.rb
    plugins/global-shortcut/test/test_global_shortcut.rb
    plugins/global-shortcut/test/test_setup.rb
    plugins/notification/test/test_macos_notifications.rb
    plugins/notification/test/test_windows_notifications.rb
  ].freeze

  # The plugins' real-window tests that a person's click could fail: each
  # ends a dialog sheet, which a click on it would end first. They run
  # only in test:console, which holds the desktop input lock around them,
  # with its spoken notice, on a Mac outside CI; the other real-window
  # tasks leave them out (Plan 057's amendment).
  CONSOLE = %w[
    plugins/dialog/test/test_dialog_window.rb
  ].freeze

  # The repository, which the paths here are relative to.
  ROOT = File.expand_path("..", __dir__)

  # What the real-window tasks set for their test processes, which the
  # tests' tripwire reads.
  RUN = "TOKRA_REAL_WINDOWS_RUN"

  class << self
    # The environment for a test process: TOKRA_REAL_WINDOWS_RUN=1 lets it
    # open real windows (test/support/real_windows_run.rb) if +windows+,
    # and is unset otherwise, whatever the shell exported.
    def run_env(windows) = { RUN => (windows ? "1" : nil) }

    # Whether the test file at +path+ (relative to the repository) opens
    # real windows. +source+ is its text.
    def test_file?(path, source = File.read(File.join(ROOT, path)))
      path.start_with?(INTEGRATION) || NAMED.include?(path) || source.match?(MARKER)
    end

    # The test files among +paths+ that open real windows, except the
    # CONSOLE tests, which test:console runs, and the rest.
    def split(paths)
      windows, rest = paths.partition { |path| test_file?(path) }
      [windows - CONSOLE, rest]
    end

    # +plugin+'s test files (relative to it), those that open real windows
    # if +windows+, else the rest, as its Rakefile's pattern finds them.
    # Neither holds its CONSOLE tests, which test:console runs.
    def plugin_tests(plugin, windows:)
      paths = Dir.glob("#{plugin}/test/**/test_*.rb", base: ROOT).sort.select { |path| test_file?(path) == windows }
      paths -= CONSOLE
      paths.map { |path| path.delete_prefix("#{plugin}/") }
    end

    # The CONSOLE tests of +plugin+, relative to it, or with none given,
    # the core ones, relative to the repository.
    def console_tests(plugin = nil)
      return CONSOLE.reject { |path| path.start_with?("plugins/") } unless plugin

      CONSOLE.select { |path| path.start_with?("#{plugin}/") }.map { |path| path.delete_prefix("#{plugin}/") }
    end
  end
end
