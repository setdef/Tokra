# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for tray_test.rb: a real tray icon (plan 043). It needs no page,
# so it runs on Windows too.
#
# Once the loop runs, the main thread builds a tray with an icon, a
# tooltip, a title, and a menu. A background thread then reads it back
# from the platform (PlatformTray), changes each attribute, hides and
# shows it, reads its rect, sends it events through tray-icon's own
# dispatch, never a click, and reports what each listener heard. Last it
# removes the tray and reads the platform again. No menu opens: Windows'
# left click is told not to open one first. It prints REPORT <json> and
# exits.
#
#   bundle exec ruby test/integration/fixtures/tray/app.rb

require_relative "../../support/fixture_app"
require_relative "../../support/platform_tray"
require "tmpdir"

$stdout.sync = true

module TrayFixture
  # What the listeners heard, in order.
  HEARD = Thread::Queue.new

  # The next +count+ things the listeners heard, waiting up to five
  # seconds for each.
  def self.heard(count)
    Array.new(count) { HEARD.pop(timeout: 5) }.compact
  end

  # A 16 by 16 icon of one color.
  def self.icon(red)
    Tokra::Image.new(rgba: [red, 0x80, 0xE0, 0xFF].pack("C*") * 256, width: 16, height: 16)
  end
end

icon_dir = Dir.mktmpdir("tokra-tray-fixture")
app = Tokra::Builder.default.title("Tokra integration: tray #{Process.pid}").size(320, 240)
  .on_tray_icon_event(&Ractor.shareable_proc { |_handle, event|
    TrayFixture::HEARD << "app:#{event.class.name.split('::').last}:#{event.id}"
  })
  .build
FixtureApp.background(app)

app.run do |handle, event|
  next unless event.is_a?(Tokra::RunEvent::Ready)

  menu = Tokra::Menu::MenuBuilder.with_id(handle, "fixture-tray-menu").text("tray-open", "Open").build
  tray = Tokra::Tray::TrayIconBuilder.with_id("fixture-tray")
    .icon(TrayFixture.icon(0x20)).tooltip("Fixture Tip").title("Fixture Title").menu(menu).temp_dir_path(icon_dir)
    .on_tray_icon_event { |heard_tray, heard| TrayFixture::HEARD << "tray:#{heard.class.name.split('::').last}:#{heard_tray.id}" }
    .build(handle)
  Thread.new do
    report = {}
    on_main = lambda do |&work|
      answer = Thread::Queue.new
      handle.run_on_main_thread do
        answer << work.call
      rescue => e
        answer << "#{e.class}: #{e.message}"
      end
      answer.pop
    end
    read = -> { on_main.call { PlatformTray.read(icon_dir) } }
    report["built"] = read.call
    report["found"] = handle.tray_by_id("fixture-tray").equal?(tray)
    tray.set_tooltip("Changed Tip")
    tray.set_title("Changed Title")
    tray.set_icon(nil)
    report["changed"] = read.call
    tray.set_menu(nil)
    report["menu_removed"] = read.call
    tray.set_menu(menu)
    tray.set_icon(TrayFixture.icon(0xE0))
    report["icon_again"] = read.call
    tray.set_visible(false)
    report["hidden"] = read.call
    tray.set_visible(true)
    report["shown"] = read.call
    report["rect"] = tray.rect&.then { |rect| [rect.position.class.name, rect.size.width, rect.size.height] }
    tray.set_show_menu_on_left_click(false)
    sent = on_main.call { PlatformTray.dispatch(%i[enter move leave click_down click_up double_click]) }
    report["sent"] = sent.map(&:to_s)
    report["heard"] = TrayFixture.heard(sent.size * 2)
    report["removed"] = handle.remove_tray_by_id("fixture-tray").equal?(tray)
    report["after_remove"] = read.call
    report["found_after_remove"] = handle.tray_by_id("fixture-tray")
    puts "REPORT #{JSON.generate(report)}"
    handle.exit(0)
  rescue => e
    puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(5))}"
    handle.exit(1)
  end
end
