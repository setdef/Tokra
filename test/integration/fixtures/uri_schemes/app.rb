# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for uri_schemes_test.rb: custom URI schemes the builder holds
# (plan 067). The window loads second://localhost/, which a synchronous
# handler serves, harness and reports included; its page fetches from
# third://, which an asynchronous handler answers from a thread of its
# own, and invokes a command from the second scheme's origin. Run by hand
# to watch it:
#
#   bundle exec ruby test/integration/fixtures/uri_schemes/app.rb --wait

require_relative "../../support/fixture_app"
require "stringio"
require "uri"

module UriSchemesFixture
  # The harness's own site, served over second:// here instead of
  # tokra://.
  @site = nil

  class << self
    attr_accessor :site

    # Answers +request+, a request on the second scheme, with the site's
    # Rack response, or with what the handler saw for /whoami.
    def serve(context, request)
      path = URI(request.uri).path
      return json(seen(context, request)) if path == "/whoami"

      env = {
        "REQUEST_METHOD" => request.method,
        "PATH_INFO" => path.empty? ? "/" : path,
        "SERVER_NAME" => "localhost",
        "rack.input" => StringIO.new(request.body),
      }
      status, headers, body = site.call(env)
      Tokra::Response.new(status:, headers:, body: body.join)
    end

    # What a handler saw of +request+: the webview that asked, the scheme
    # its protocol was registered under, and the URI as wry handed it.
    def seen(context, request)
      { label: context.webview_label, scheme: request.scheme, uri: request.uri }
    end

    # +value+ as JSON any origin may read: the page comes from second://,
    # another origin than third://, so third's answer needs CORS.
    def json(value)
      Tokra::Response.new(status: 200, body: JSON.generate(value),
        headers: { "content-type" => "application/json", "access-control-allow-origin" => "*" })
    end
  end

  # The second scheme: synchronous, on the main thread.
  SECOND = Ractor.shareable_proc do |context, request|
    UriSchemesFixture.serve(context, request)
  end

  # The third scheme: answers from a thread of its own, so the answer
  # reaches the main thread through the event loop (ADR 012, decision 6).
  THIRD = Ractor.shareable_proc do |context, request, responder|
    seen = UriSchemesFixture.seen(context, request)
    Thread.new do
      responder.respond(UriSchemesFixture.json(seen.merge(thread: (Thread.current == Thread.main) ? "main" : "other")))
    end
  end

  # Answers "whereami" with the webview that invoked it.
  INVOKE = Ractor.shareable_proc do |invoke|
    next false unless invoke.command == "whereami"

    invoke.resolve(invoke.webview.label)
    true
  end
end

options = FixtureApp.options(ARGV)
UriSchemesFixture.site = FixtureApp::Site.new(__dir__, options)

FixtureApp.builder(UriSchemesFixture.site)
  .register_uri_scheme_protocol("second", &UriSchemesFixture::SECOND)
  .register_asynchronous_uri_scheme_protocol("third", &UriSchemesFixture::THIRD)
  .invoke_handler(&UriSchemesFixture::INVOKE)
  .run(Tokra.generate_context)
