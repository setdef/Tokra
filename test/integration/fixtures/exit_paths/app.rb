# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for exit_paths_test.rb: how a real app ends. The page invokes once,
# reports, and (without --wait) exits through AppHandle#exit with
# --exit-code. The fixture plugin prints the run events it hears, and an
# at_exit hook prints AT_EXIT, so the test sees Ruby's own exit run.
#
# --raise-on-page-load makes the page-load hook raise when the page starts
# loading, before its script sends anything, so every invoke after it ran on
# a loop that survived a Ruby exception.
#
# To close the window by hand (the one exit path the tests cannot drive):
#
#   bundle exec ruby test/integration/fixtures/exit_paths/app.rb --wait

require_relative "../../support/fixture_app"

options = FixtureApp.options(ARGV, :raise_on_page_load)
at_exit { puts "AT_EXIT" }

builder = FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "exit paths")
  .invoke_handler(&Ractor.shareable_proc { |invoke|
    next false unless invoke.command == "ping"

    invoke.resolve("PONG")
    true
  })

if options[:raise_on_page_load]
  builder.on_page_load(&Ractor.shareable_proc { |_webview, payload|
    raise "exit-paths: deliberate page-load failure" if payload.started? && payload.url == "tokra://localhost/"
  })
end

builder.run
