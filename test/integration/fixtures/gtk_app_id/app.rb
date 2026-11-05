# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for gtk_app_id_test.rb: an app built from the tokra.conf.json
# beside it, whose app.enableGTKAppId hands its identifier to the event
# loop as the GTK application id (plan 054, phase 4). It opens no window.
# Once the loop runs, a background thread asks the session bus whether
# that name has an owner, which on Linux it has because GTK registered
# the app under it (tao platform_impl/linux/event_loop.rs:223-230), prints
# REPORT <json>, and exits.
#
#   bundle exec ruby test/integration/fixtures/gtk_app_id/app.rb

require_relative "../../support/fixture_app"

# Whether the session bus has an owner for +name+, as dbus-send prints
# the answer to org.freedesktop.DBus.NameHasOwner, or +nil+ off Linux.
def name_has_owner(name)
  return unless Tokra::Utils::Platform::Target.current == Tokra::Utils::Platform::Target::Linux

  reply = IO.popen(
    [
      "dbus-send",
      "--session",
      "--print-reply",
      "--dest=org.freedesktop.DBus",
      "/org/freedesktop/DBus",
      "org.freedesktop.DBus.NameHasOwner",
      "string:#{name}",
],
    err: [:child, :out],
    &:read
  )
  reply[/boolean (true|false)/, 1] || reply
end

app = Tokra::Builder.default.build(Tokra.generate_context)
FixtureApp.background(app)

app.run do |handle, event|
  next unless event.is_a?(Tokra::RunEvent::Ready)

  Thread.new do
    config = handle.config
    report = {
      "app_id" => Tokra::App.gtk_app_id(config),
      "name_has_owner" => name_has_owner(config.identifier),
    }
    puts "REPORT #{JSON.generate(report)}"
    handle.exit(0)
  rescue => e
    puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(5))}"
    handle.exit(1)
  end
end
