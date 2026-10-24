# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for ipc_transport_test.rb: the real @tauri-apps/api invoke over
# ipc://, resolving and rejecting. Run by hand to watch it:
#
#   bundle exec ruby test/integration/fixtures/ipc_transport/app.rb --wait

require_relative "../../support/fixture_app"

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "ipc transport")
  .with_global_tauri
  .invoke_handler(&Ractor.shareable_proc { |invoke|
    next false unless invoke.command == "ping"

    invoke.resolve("#{invoke.payload['message']}PONG")
    true
  })
  .run
