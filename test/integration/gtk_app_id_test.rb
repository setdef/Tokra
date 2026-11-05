# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A real app whose tokra.conf.json turns on app.enableGTKAppId registers
# with GTK under its identifier on Linux, as Tauri's does
# (app.rs:2122-2133; tauri-runtime-wry lib.rs:2779-2790), so the session
# bus has an owner for that name while the app runs. Elsewhere the app
# runs without one, as Tauri compiles the id only for Linux and the BSDs.
# The fixture opens no window and loads no page.
class GtkAppIdTest < RealApp::TestCase
  IDENTIFIER = "com.tokra.integration.gtk-app-id"

  def self.page?
    false
  end

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("gtk_app_id") }
    assert_finished @run
    assert_equal 0, @run.status, @run.describe
    @report = @run.report
    refute_nil @report, "the fixture printed no report\n#{@run.describe}"
    refute @report.key?("error"), @report.inspect
  end

  def test_the_loop_registers_the_identifier_on_linux
    if Tokra::Utils::Platform::Target.current == Tokra::Utils::Platform::Target::Linux
      assert_equal IDENTIFIER, @report["app_id"]
      assert_equal "true", @report["name_has_owner"]
    else
      assert_nil @report["app_id"]
    end
  end
end
