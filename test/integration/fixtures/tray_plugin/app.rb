# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for tray_plugin_test.rb: the page drives the tray plugin with
# the vendored @tauri-apps/api TrayIcon class (plan 043). A fixture plugin
# reads the tray back from the platform and sends it events through
# tray-icon's own dispatch (PlatformTray), on the main thread, since the
# page cannot. No menu opens.
#
#   bundle exec ruby test/integration/fixtures/tray_plugin/app.rb [--wait]

require_relative "../../support/fixture_app"
require_relative "../../support/platform_tray"
require "tmpdir"

# Reads and pokes the page's tray for it.
class TrayReader < Tokra::Plugin
  # Where tray-icon writes the icon on Linux.
  DIR = Dir.mktmpdir("tokra-tray-plugin")

  def name
    "tray-fixture"
  end

  def extend_api(invoke)
    case invoke.command
    when "dir" then invoke.resolve(DIR)
    when "read" then invoke.resolve(PlatformTray.read(DIR))
    when "dispatch" then invoke.resolve(PlatformTray.dispatch(invoke.payload.fetch("kinds").map(&:to_sym)).map(&:to_s))
    when "os" then invoke.resolve(Tokra::Menu.os.to_s)
    else return false
    end
    true
  end
end

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "tray plugin", plugins: [TrayReader])
  .with_global_tauri
  .run
