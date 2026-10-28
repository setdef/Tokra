# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for menu_plugin_test.rb: the core menu plugin through the real
# menu classes of @tauri-apps/api (plan 042). The page builds a menu, makes
# it the app's, and asks plugin:menu-fixture|activate to activate one of
# its items through the platform's own dispatch (PlatformMenu), so the
# item's action hears the click through muda and its channel. Run by hand
# to watch it:
#
#   bundle exec ruby test/integration/fixtures/menu_plugin/app.rb --wait

require_relative "../../support/fixture_app"
require_relative "../../support/platform_menu"

# Activates a menu item by its submenu's title and its own, on the main
# thread, where the IPC handler runs.
class MenuActivator < Tokra::Plugin
  def name
    "menu-fixture"
  end

  def extend_api(invoke)
    window = app.get_window("main")
    payload = invoke.payload
    case invoke.command
    when "activate"
      invoke.resolve(PlatformMenu.activate(window, window.title, payload.fetch("submenu"), payload.fetch("title")))
    when "image" then invoke.resolve(PlatformMenu.image?(window, window.title, payload.fetch("path")))
    else return false
    end
    true
  end
end

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "menu plugin", plugins: [MenuActivator])
  .with_global_tauri
  .run
