# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for origin_acl_test.rb: the local-origin stopgap (ADR 010 §6).
# A frame from tokra://foreign.test, a host other than localhost, sends the
# same invoke the app's own page sends, over both transports. Run by hand to
# watch it:
#
#   bundle exec ruby test/integration/fixtures/origin_acl/app.rb --wait

require_relative "../../support/fixture_app"

FOREIGN_HOST = "foreign.test"

options = FixtureApp.options(ARGV)
invoke_key = nil

# TEST FIXTURE ONLY. Never write the invoke key into a page an app serves:
# anyone holding it can invoke from any frame that reaches the webview. This
# fixture does it on purpose, for one foreign host only, because that is the
# threat the stopgap exists for: wry injects the key into every top-level
# document, so a foreign page can hold it. The check must reject it anyway.
foreign_page = lambda do |env|
  next [404, { "content-type" => "text/plain" }, ["not found"]] unless env["SERVER_NAME"] == FOREIGN_HOST

  html = File.read(File.join(__dir__, "foreign.html")).sub("__INVOKE_KEY__") { JSON.generate(invoke_key) }
  [200, { "content-type" => "text/html; charset=utf-8" }, [html]]
end

app = FixtureApp.builder(FixtureApp::Site.new(__dir__, options, { "/foreign.html" => foreign_page }), "origin ACL")
  .invoke_handler(&Ractor.shareable_proc { |invoke|
    next false unless invoke.command == "ping"

    invoke.resolve("PONG")
    true
  })
  .build
invoke_key = app.invoke_key
app.run
