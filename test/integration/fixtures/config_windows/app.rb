# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for config_windows_test.rb: an app built from the tokra.conf.json
# beside it, which lists three windows, one with create set to false (plan
# 054, 054a-3). The setup hook records the windows it finds; on Ready the
# app prints one report of them and of the real windows' titles, then
# exits. It loads no page, so it runs on Windows too.
#
#   bundle exec ruby test/integration/fixtures/config_windows/app.rb

require_relative "../../support/fixture_app"

module ConfigWindowsFixture
  # The labels the setup hook found, in the order the app built them.
  SETUP = Ractor.shareable_proc do |app|
    Thread.current[:config_windows_setup] = app.webview_windows.keys
    FixtureApp.background(app)
  end
end

app = Tokra::Builder.default.setup(&ConfigWindowsFixture::SETUP).build(Tokra.generate_context)
app.run do |handle, event|
  case event
  when Tokra::RunEvent::Ready
    windows = handle.webview_windows
    windows.each_value { |window| FixtureApp.keep_in_sight(window.window) }
    report = {
      "setup" => Thread.current[:config_windows_setup],
      "titles" => windows.transform_values { |window| window.window.title },
      "configured" => handle.config.app.windows.map { |window| [window.label, window.create] },
      "package" => handle.package_info.name,
    }
    puts "REPORT #{JSON.generate(report)}"
    $stdout.flush
    handle.exit(0)
  end
end
