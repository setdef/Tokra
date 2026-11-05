# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real app built from its tokra.conf.json shows the tray the config's
# app.trayIcon describes, built before the setup hook with the id "main"
# and the config's icon, title, and tooltip, and its events reach the
# app's listener and the run callback, as Tauri's Builder::build builds
# it (app.rs:2265-2287; plan 049, part B). The fixture opens no window,
# loads no page, and opens no menu, so this runs on Windows too.
class ConfigTrayTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("config_tray") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def os = Tokra::Menu.os

  def test_the_setup_hook_finds_the_configured_tray_as_main
    assert_equal "main", @report["setup"]
    assert_equal "main", @report["found"]
  end

  def test_the_platform_shows_the_configured_icon_title_and_tooltip
    assert_equal ["Config Title", "Config Tip"], @report["configured"]
    case os
    when :macos
      assert_equal [{ "image" => true, "tooltip" => "Config Tip", "title" => "Config Title", "menu" => nil }], @report["built"]
    when :windows then assert_equal 1, @report["built"]
    else
      assert_equal 1, @report["built"].size, @report["built"].inspect
      assert_match(/\Atray-icon-\d+-0\.png\z/, @report["built"].first)
    end
  end

  # The tray has no listener of its own: the app's listener hears each
  # event, then the run callback (app.rs:2453-2472, 2488-2494).
  def test_each_event_reaches_the_app_then_the_run_callback
    kinds = { macos: %w[Enter Move Leave], windows: %w[Enter Click Click DoubleClick], linux: [] }.fetch(os)
    assert_equal kinds.size, @report["sent"].size
    assert_equal kinds.flat_map { |kind| ["app:#{kind}:main", "run:#{kind}:main"] }, @report["heard"]
  end
end
