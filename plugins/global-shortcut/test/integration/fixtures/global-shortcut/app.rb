# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for test_global_shortcut_window.rb: the global-shortcut plugin in
# a real window, called from the page through Tauri's own api-iife.js. Run
# by hand to watch it:
#
#   cd plugins/global-shortcut && bundle exec ruby test/integration/fixtures/global-shortcut/app.rb --wait
#
# The page waits for key presses only when FIXTURE_PRESSES is set, which the
# Linux test does once it has pointed the app at its own Xvfb; it prints
# REGISTERED when its shortcut is in, and the test presses the keys there.
# Elsewhere it registers and unregisters without waiting for a press, so
# nothing reaches a person's keyboard.

require_relative "../../../../../../test/integration/support/fixture_app"
require "tokra-global-shortcut"

module GlobalShortcutFixture
  # The shortcut the page registers: one xdotool can press on Linux, and
  # on other systems one nobody uses.
  SHORTCUT = ENV.key?("FIXTURE_PRESSES") ? "ctrl+alt+shift+F24" : "ctrl+alt+shift+super+F19"

  # The page's facts, Tauri's api-iife.js, and the line the test waits for.
  ROUTES = {
    "/global-shortcut.json" => lambda { |_env|
      [
        200,
        { "content-type" => "application/json" },
        [JSON.generate(presses: ENV.key?("FIXTURE_PRESSES"), shortcut: SHORTCUT)],
]
    },
    "/api-iife.js" => lambda { |_env|
      [200, { "content-type" => "text/javascript" }, [File.read(File.join(__dir__, "api-iife.js"))]]
    },
    "/registered" => lambda { |_env|
      puts "REGISTERED"
      $stdout.flush
      [204, {}, []]
    },
  }.freeze
end

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options, GlobalShortcutFixture::ROUTES), "global-shortcut",
  plugins: [Tokra::Plugins::GlobalShortcut::Plugin])
  .with_global_tauri
  .run
