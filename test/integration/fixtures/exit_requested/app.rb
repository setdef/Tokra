# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for exit_requested_test.rb: the last window closes, and the app
# exits or keeps running (Plan 038). The page reports, then asks Ruby to
# close the window through plugin:exit-requested|close, which calls
# Window#close: the close request, the window's destruction, and the exit
# request with no code follow as they do for the close button.
#
# --prevent-exit makes the plugin prevent the exit request with no code.
# The app then runs with no window. A thread waits SETTLE seconds, prints
# how many windows are left (WINDOWS) and what the closed window's title
# answers (TITLE), and calls AppHandle#exit with --exit-code, which the
# plugin does not prevent.

require_relative "../../support/fixture_app"

options = FixtureApp.options(ARGV, :prevent_exit)
at_exit { puts "AT_EXIT" }

module ExitRequestedFixture
  # Seconds the windowless app runs before it asks to exit.
  SETTLE = 0.5

  # What the plugin was asked to do, set before the app runs.
  OPTIONS = {}

  # Closes the window, and prevents the exit that follows when asked to.
  class Plugin < Tokra::Plugin
    def name
      "exit-requested"
    end

    def extend_api(invoke)
      return false unless invoke.command == "close"

      @window = app.get_window("main")
      invoke.resolve(nil)
      @window.close
      true
    end

    def on_event(app, event)
      return unless event.is_a?(Tokra::RunEvent::ExitRequested) && event.code.nil?
      return unless OPTIONS[:prevent_exit]

      event.api.prevent_exit
      puts "PREVENTED"
      window = @window
      Thread.new do
        sleep SETTLE
        puts "WINDOWS #{app.windows.size}"
        title = begin
          window.title
        rescue Tokra::Error => e
          e.message
        end
        puts "TITLE #{title}"
        app.exit(OPTIONS.fetch(:exit_code))
      end
    end
  end
end

ExitRequestedFixture::OPTIONS.merge!(options).freeze

FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "exit requested", plugins: [ExitRequestedFixture::Plugin])
  .run
