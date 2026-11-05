# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for config_tray_test.rb: an app built from the tokra.conf.json
# beside it, whose app.trayIcon describes a tray with an icon, a title,
# and a tooltip, and which lists no window (plan 049, part B). App#run
# builds the tray before the setup hook, which records whether it finds
# it. Once the loop runs, a background thread reads the tray back from
# the platform (PlatformTray), sends it events through tray-icon's own
# dispatch, never a click that could open anything, and reports what the
# app's listener and the run callback heard. It prints REPORT <json> and
# exits.
#
#   bundle exec ruby test/integration/fixtures/config_tray/app.rb

require_relative "../../support/fixture_app"
require_relative "../../support/platform_tray"
require "tmpdir"

# On Linux tray-icon writes the config tray's icon, which has no temp
# directory of its own, under $XDG_RUNTIME_DIR/tray-icon (tray-icon 0.21.0
# platform_impl/gtk/mod.rs:118-137), so the fixture gives it a directory
# no other process writes to, before anything reads the variable.
ENV["XDG_RUNTIME_DIR"] = Dir.mktmpdir("tokra-config-tray")
runtime_dir = ENV.fetch("XDG_RUNTIME_DIR")
at_exit { FileUtils.remove_entry(runtime_dir, true) }

module ConfigTrayFixture
  # Where tray-icon writes the icon on Linux.
  ICON_DIR = File.join(ENV.fetch("XDG_RUNTIME_DIR"), "tray-icon")

  # What the app's listener and the run callback heard, in order.
  HEARD = Thread::Queue.new

  # The next +count+ things heard, waiting up to the fixture's patience
  # for them all (FixtureApp.take).
  def self.heard(count)
    FixtureApp.take(HEARD, count)
  end

  # The kind of a Tray::TrayIconEvent, such as "Enter".
  def self.kind(event)
    event.class.name.split("::").last
  end

  # Records the id of the tray the setup hook finds as "main".
  SETUP = Ractor.shareable_proc do |app|
    Thread.current[:config_tray_setup] = app.tray_by_id("main")&.id&.to_s
  end

  LISTENER = Ractor.shareable_proc do |_handle, event|
    ConfigTrayFixture::HEARD << "app:#{ConfigTrayFixture.kind(event)}:#{event.id}"
  end
end

app = Tokra::Builder.default
  .on_tray_icon_event(&ConfigTrayFixture::LISTENER)
  .setup(&ConfigTrayFixture::SETUP)
  .build(Tokra.generate_context)
FixtureApp.background(app)

app.run do |handle, event|
  case event
  when Tokra::RunEvent::TrayIconEvent
    tray_event = event.event
    ConfigTrayFixture::HEARD << "run:#{ConfigTrayFixture.kind(tray_event)}:#{tray_event.id}"
  when Tokra::RunEvent::Ready
    setup = Thread.current[:config_tray_setup]
    Thread.new do
      report = { "setup" => setup }
      on_main = lambda do |&work|
        answer = Thread::Queue.new
        handle.run_on_main_thread do
          answer << work.call
        rescue => e
          answer << "#{e.class}: #{e.message}"
        end
        answer.pop
      end
      report["built"] = on_main.call { PlatformTray.read(ConfigTrayFixture::ICON_DIR) }
      tray = handle.tray_by_id("main")
      report["found"] = tray&.id&.to_s
      report["configured"] = handle.config.app.tray_icon.then { |config| [config.title, config.tooltip] }
      sent = on_main.call { PlatformTray.dispatch(%i[enter move leave click_down click_up double_click]) }
      report["sent"] = sent.map(&:to_s)
      report["heard"] = ConfigTrayFixture.heard(sent.size * 2)
      puts "REPORT #{JSON.generate(report)}"
      handle.exit(0)
    rescue => e
      puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(5))}"
      handle.exit(1)
    end
  end
end
