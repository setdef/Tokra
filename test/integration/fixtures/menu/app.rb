# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for menu_test.rb: a real app menu (plan 042). It needs no page,
# so it runs on Windows too.
#
# The builder sets the app's menu. Once the loop runs, a background thread
# reads an item's text through the main thread, then the main thread reads
# the menu back from the platform (-[NSApp mainMenu] on macOS, GetMenu on
# Windows, the window's GtkMenuBar on Linux) and activates two items
# through the platform's own dispatch (-[NSMenu
# performActionForItemAtIndex:], WM_COMMAND, gtk_menu_item_activate),
# never a click or a key, so each event travels muda's path to the app.
# It reports what each listener heard, then takes the menu away and reads
# the platform again. It prints REPORT <json> and exits.
#
#   bundle exec ruby test/integration/fixtures/menu/app.rb

require_relative "../../support/fixture_app"
require_relative "../../support/platform_menu"

$stdout.sync = true

module MenuFixture
  # A title no other window on the display has, so the GTK reader finds
  # this window.
  TITLE = "Tokra integration: menu #{Process.pid}".freeze

  # What the listeners heard, in order.
  HEARD = Thread::Queue.new

  # The next +count+ things the listeners heard, waiting up to five
  # seconds for each.
  def self.heard(count)
    Array.new(count) { HEARD.pop(timeout: 5) }.compact
  end
end

app = Tokra::Builder.default.title(MenuFixture::TITLE).size(320, 240)
  .menu(&Ractor.shareable_proc { |handle|
    Tokra::Menu::MenuBuilder.with_id(handle, "fixture-bar")
      .item(Tokra::Menu::SubmenuBuilder.with_id(handle, "fixture-app", "Fixture")
        .item(Tokra::Menu::MenuItemBuilder.with_id("fixture-item", "Fixture Item").accelerator("CmdOrCtrl+Shift+F").build(handle))
        .item(Tokra::Menu::CheckMenuItemBuilder.with_id("fixture-check", "Fixture Check").checked(false).build(handle))
        .build)
      .item(Tokra::Menu::SubmenuBuilder.with_id(handle, "fixture-tools", "Tools").text("tools-run", "Run Tool").build)
      .build
  })
  .on_menu_event(&Ractor.shareable_proc { |_handle, event| MenuFixture::HEARD << "app:#{event.id}" })
  .build
FixtureApp.background(app)

app.run do |handle, event|
  case event
  when Tokra::RunEvent::MenuEvent then MenuFixture::HEARD << "run:#{event.event.id}"
  when Tokra::RunEvent::Ready
    window = handle.get_window("main")
    window.on_menu_event { |w, heard| MenuFixture::HEARD << "window:#{w.label}:#{heard.id}" }
    Thread.new do
      report = {}
      menu = handle.menu
      report["menu_id"] = menu.id.to_s
      report["thread_text"] = menu.get("fixture-tools").items.first.text
      on_main = lambda do |&work|
        answer = Thread::Queue.new
        handle.run_on_main_thread do
          answer << work.call
        rescue => e
          answer << "#{e.class}: #{e.message}"
        end
        answer.pop
      end
      report["tree"] = on_main.call { PlatformMenu.tree(window, MenuFixture::TITLE) }
      report["activated"] = on_main.call { PlatformMenu.activate(window, MenuFixture::TITLE, "Fixture", "Fixture Item") }
      report["heard"] = MenuFixture.heard(3)
      check = menu.get("fixture-app").get("fixture-check")
      report["checked_before"] = check.is_checked
      report["activated_check"] = on_main.call { PlatformMenu.activate(window, MenuFixture::TITLE, "Fixture", "Fixture Check") }
      report["heard_check"] = MenuFixture.heard(3)
      report["checked_after"] = check.is_checked
      report["removed"] = handle.remove_menu&.id.to_s
      report["window_menu"] = window.menu&.id.to_s
      report["tree_after_remove"] = on_main.call { PlatformMenu.tree(window, MenuFixture::TITLE) }
      puts "REPORT #{JSON.generate(report)}"
      handle.exit(0)
    rescue => e
      puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(5))}"
      handle.exit(1)
    end
  end
end
