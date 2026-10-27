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
# The page sends notifications only when FIXTURE_SERVER_LOG names the
# log of the Linux test's own dunst, which the test sets once it has
# pointed D-Bus at that dunst; elsewhere it checks everything short of a
# send, so no notification reaches a person's screen.
#
# A send goes out on a thread of its own, and the app's exit ends one
# still under way, as Tauri's exit drops the task its send spawned
# (desktop.rs:217-219). So before it finishes, the page reads that log
# until every notification it sent has reached the server.

require_relative "../../../../../../test/integration/support/fixture_app"
require "tokra-notification"

module NotificationFixture
  # The page's facts: whether it may send, what has reached the test's
  # server, and Tauri's api-iife.js.
  ROUTES = {
    "/notification.json" => lambda { |_env|
      [200, { "content-type" => "application/json" }, [JSON.generate(sends: ENV.key?("FIXTURE_SERVER_LOG"))]]
    },
    "/server.log" => lambda { |_env|
      [200, { "content-type" => "text/plain; charset=utf-8" }, [File.read(ENV.fetch("FIXTURE_SERVER_LOG"))]]
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
