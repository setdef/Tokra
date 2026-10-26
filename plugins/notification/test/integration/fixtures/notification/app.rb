# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for test_notification_window.rb: the notification plugin in a
# real window, called from the page through Tauri's own api-iife.js and
# the window.Notification the plugin's init script defines. Run by hand
# to watch it:
#
#   cd plugins/notification && bundle exec ruby test/integration/fixtures/notification/app.rb --wait
#
# The page sends notifications only when FIXTURE_SENDS is set, which the
# Linux test does once it has pointed D-Bus at its own dunst; elsewhere it
# checks everything short of a send, so no notification reaches a
# person's screen.

require_relative "../../../../../../test/integration/support/fixture_app"
require "tokra-notification"

module NotificationFixture
  # The page's facts: whether it may send, and Tauri's api-iife.js.
  ROUTES = {
    "/notification.json" => lambda { |_env|
      [200, { "content-type" => "application/json" }, [JSON.generate(sends: ENV.key?("FIXTURE_SENDS"))]]
    },
    "/api-iife.js" => lambda { |_env|
      [200, { "content-type" => "text/javascript" }, [File.read(File.join(__dir__, "api-iife.js"))]]
    },
  }.freeze
end

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options, NotificationFixture::ROUTES), "notification",
  plugins: [Tokra::Plugins::Notification::Plugin])
  .with_global_tauri
  .run
