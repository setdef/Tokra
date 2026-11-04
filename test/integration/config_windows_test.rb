# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real app built from its tokra.conf.json opens the windows the config's
# app.windows lists, in order and before the setup hook, skipping one whose
# create is false, as Tauri's setup does (app.rs:2370-2384; plan 054,
# 054a-3). The fixture loads no page, so this runs on Windows too.
class ConfigWindowsTest < RealApp::TestCase
  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("config_windows") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
  end

  def test_the_setup_hook_finds_the_created_windows_in_order
    assert_equal %w[first second], @report["setup"], @run.describe
  end

  def test_each_real_window_has_its_configured_title
    assert_equal({
      "first" => "Tokra integration: config windows (first)",
      "second" => "Tokra integration: config windows (second)",
    }, @report["titles"], @run.describe)
  end

  def test_the_skipped_window_stays_in_the_config_and_the_package_is_named_for_it
    assert_equal [["first", true], ["later", false], ["second", true]], @report["configured"]
    assert_equal "Tokra integration config windows", @report["package"]
  end
end
