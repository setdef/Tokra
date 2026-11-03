# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for event_test.rb: events between Ruby and the page through the
# vendored @tauri-apps/api (plan 047). Ruby listens as the app and as the
# window and answers what it hears; the page asks Ruby to emit, to resize
# its window, and to move it, and listens for each through the real
# client. It prints each focus change its window hears (plan 052). Run by
# hand to watch it:
#
#   bundle exec ruby test/integration/fixtures/event/app.rb --wait

require_relative "../../support/fixture_app"

# Emits for the page, echoes the page's events, and resizes and moves the
# window, on the main thread, where the IPC handler runs.
class EventFixture < Tokra::Plugin
  def name
    "event-fixture"
  end

  def on_event(app, event)
    return unless event.is_a?(Tokra::RunEvent::Ready)

    app.listen("page-says") { |heard| app.emit("ruby-heard", { "payload" => heard.payload, "as" => "app" }) }
    app.get_window("main").listen("to-window") do |heard|
      app.emit("ruby-heard", { "payload" => heard.payload, "as" => "window" })
    end
  end

  def extend_api(invoke)
    window = app.get_window("main")
    payload = invoke.payload
    case invoke.command
    when "emit"
      payload.fetch("names").each { |name| app.emit(name, payload["payload"]) }
      invoke.resolve(nil)
    when "resize"
      window.set_size(Tokra::PhysicalSize.new(width: payload.fetch("width"), height: payload.fetch("height")))
      invoke.resolve(nil)
    when "move"
      window.set_position(Tokra::PhysicalPosition.new(x: payload.fetch("x"), y: payload.fetch("y")))
      invoke.resolve(nil)
    when "inner_size" then invoke.resolve(window.inner_size.to_h)
    when "outer_position" then invoke.resolve(window.outer_position.to_h)
    else return false
    end
    true
  end
end

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "events", plugins: [EventFixture])
  .with_global_tauri
  # Focus only: FixtureApp::Plugin prints the close and its end, and when a
  # platform reports focus depends on its window manager, so no other
  # fixture's output changes.
  .on_window_event(&Ractor.shareable_proc { |window, event|
    puts "EVENT window #{window.label} #{event.class.name} #{event.focused}" if event.is_a?(Tokra::WindowEvent::Focused)
  })
  .run
