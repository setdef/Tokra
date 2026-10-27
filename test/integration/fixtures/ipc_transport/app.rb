# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for ipc_transport_test.rb: the real @tauri-apps/api invoke over
# ipc://, resolving and rejecting, raw bytes both ways, and a mismatched
# invoke key left unanswered. Run by hand to watch it:
#
#   bundle exec ruby test/integration/fixtures/ipc_transport/app.rb --wait

require_relative "../../support/fixture_app"

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "ipc transport")
  .with_global_tauri
  .invoke_handler(&Ractor.shareable_proc { |invoke|
    case invoke.command
    when "ping"
      invoke.resolve("#{invoke.payload['message']}PONG")
    when "reverse_bytes"
      # Bytes in, bytes out, as the fs plugin's write_file and read_file
      # take and give them: raw over ipc://, a number array over
      # postMessage (Plan 033).
      body = Tokra::Ipc::Request.from_command(invoke).body
      bytes = body.is_a?(Array) ? body.pack("C*") : body.to_s.b
      invoke.resolve(Tokra::Ipc::Response.new(bytes.reverse))
    when "describe_request"
      request = Tokra::Ipc::Request.from_command(invoke)
      invoke.resolve({
        "raw" => Tokra::Ipc::InvokeBody.raw?(request.body),
        "body" => request.body.is_a?(Array) ? request.body : request.body.to_s.bytes,
        "probe" => request.headers["x-probe"],
        "contentType" => request.headers["content-type"],
      })
    else
      next false
    end
    true
  })
  .run
