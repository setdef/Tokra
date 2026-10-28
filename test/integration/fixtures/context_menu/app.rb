# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for context_menu_test.rb: real context menus (plan 042, phase
# 3), on every platform.
#
# It pops up a menu at a position from a background thread, then a
# submenu at the pointer from the main thread. While each tracks, a timer
# on the main thread finds the platform's menu and reads its items and
# position, and a second Ruby thread, which runs only if the popup let go
# of the GVL, counts ticks and then closes the menu: on macOS by choosing
# an item of the first (-[NSMenu performActionForItemAtIndex:], sent
# through GCD's main queue) and cancelling each (-[NSMenu
# cancelTracking]), on Linux by choosing an item of the first
# (gtk_menu_shell_activate_item) and cancelling the second, on Windows by
# posting WM_CANCELMODE. A fallback timer closes a menu that thread never
# reached, which a popup holding the GVL would cause. It prints REPORT
# <json> and exits.
#
# On macOS the app keeps the Prohibited activation policy: AppKit shows
# and tracks the menu without activating the app, so it never takes the
# keyboard, and the menu closes without a click or a key. It does show on
# screen for a moment.
#
#   bundle exec ruby test/integration/fixtures/context_menu/app.rb

require_relative "../../support/fixture_app"
require_relative "../../support/platform_popup"

$stdout.sync = true

module ContextMenuFixture
  TITLE = "Tokra integration: context menu #{Process.pid}".freeze

  # What the main thread and the listeners did, in order.
  LOG = Thread::Queue.new

  # Shows a context menu with +show+, which returns once it closes, and
  # reports what happened while it tracked. +labels+ are the items the
  # platform should hold; +choose+ is the item to choose on macOS and
  # Linux, or +nil+ to cancel.
  def self.track(handle, window, labels:, choose: nil, hmenu: nil, &show)
    shown = Thread::Queue.new
    seen = {}
    dismissed_by = Thread::Queue.new
    done = false
    # Read before the popup: the handle is a getter the main thread
    # answers, and the main thread is busy while a menu tracks.
    hwnd = (Tokra::Menu.os == :windows) ? window.window_handle.hwnd : nil
    place = (Tokra::Menu.os == :macos) ? [window.inner_position, window.scale_factor] : nil
    on_main(handle) do
      PlatformPopup::Appkit.observe if Tokra::Menu.os == :macos
      PlatformPopup.every(window, 50) do
        next false if done

        menu = PlatformPopup.find(labels)
        next true unless menu

        seen["labels"] = PlatformPopup.labels(menu, hmenu)
        seen["offset"] = PlatformPopup.offset(window, menu, TITLE, place)
        shown << menu
        false
      end
      PlatformPopup.every(window, 8000) do
        unless done
          close(PlatformPopup.find(labels, shown: false), hwnd, nil, on_main: true)
          dismissed_by << "fallback"
        end
        false
      end
    end

    ticks = 0
    ticker = Thread.new do
      loop do
        ticks += 1
        sleep 0.01
      end
    end
    closer = Thread.new do
      menu = shown.pop(timeout: 20)
      next unless menu

      at_shown = ticks
      handle.run_on_main_thread { LOG << "task sent while tracking" }
      sleep 0.3
      seen["ticks_while_tracking"] = ticks - at_shown
      close(menu, hwnd, choose, on_main: false)
      dismissed_by << "thread"
    end

    show.call
    done = true
    closer.join(5)
    ticker.kill
    seen.merge("dismissed_by" => dismissed_by.pop(timeout: 1))
  end

  # Closes +menu+: on macOS chooses +choose+, if given, and cancels,
  # through AppKit on the main thread; chooses +choose+ or cancels on
  # Linux, through GTK on the main thread; cancels on Windows, by a
  # message any thread may post or by EndMenu on the main thread.
  def self.close(menu, hwnd, choose, on_main:)
    case Tokra::Menu.os
    when :macos then close_appkit(menu, choose, on_main:)
    when :windows
      on_main ? PlatformPopup::Win32.end_menu : PlatformPopup::Win32.cancel(hwnd)
    else close_gtk(menu, choose, on_main:)
    end
  end

  def self.close_appkit(menu, choose, on_main:)
    return unless menu
    return PlatformPopup::Appkit.cancel(menu) if on_main

    PlatformPopup::Appkit.on_main_queue do
      PlatformPopup::Appkit.activate(menu, choose) if choose
      PlatformPopup::Appkit.cancel(menu)
    end
  end

  def self.close_gtk(menu, choose, on_main:)
    if on_main
      menu && PlatformPopup::Gtk.cancel(menu)
    else
      PlatformPopup::Gtk.every(0) do
        choose ? PlatformPopup::Gtk.activate(menu, choose) : PlatformPopup::Gtk.cancel(menu)
        false
      end
    end
  end

  # Runs the block on the main thread and waits for it.
  def self.on_main(handle, &work)
    answer = Thread::Queue.new
    handle.run_on_main_thread do
      answer << [work.call]
    rescue => e
      answer << e
    end
    result = answer.pop
    raise result if result.is_a?(Exception)

    result.first
  end

  def self.drain
    Array.new(LOG.size) { LOG.pop }
  end
end

app = Tokra::Builder.default.title(ContextMenuFixture::TITLE).size(320, 240)
  .on_menu_event(&Ractor.shareable_proc { |_handle, event| ContextMenuFixture::LOG << "heard #{event.id}" })
  .build
FixtureApp.background(app)

app.run do |handle, event|
  next unless event.is_a?(Tokra::RunEvent::Ready)

  window = handle.get_window("main")
  Thread.new do
    report = {}
    copy = Tokra::Menu::MenuItem.with_id(handle, "ctx-copy", "Copy Link", true, nil)
    menu = Tokra::Menu::Menu.with_items(handle, [copy, Tokra::Menu::MenuItem.with_id(handle, "ctx-open", "Open", true, nil)])
    submenu = Tokra::Menu::Submenu.with_id_and_items(handle, "ctx-more", "More", true, [
      Tokra::Menu::MenuItem.with_id(handle, "ctx-rename", "Rename", true, nil),
    ])
    windows = Tokra::Menu.os == :windows
    report["hpopupmenu"] = windows ? [menu.hpopupmenu, submenu.hpopupmenu].map(&:positive?) : nil

    report["menu"] = ContextMenuFixture.track(handle, window, labels: ["Copy Link", "Open"], choose: "Copy Link",
      hmenu: windows ? menu.hpopupmenu : nil) do
      report["menu_answer"] = menu.popup_at(window, Tokra::LogicalPosition.new(x: 30, y: 40))
      ContextMenuFixture::LOG << "menu returned"
    end
    sleep 0.3
    report["menu_log"] = ContextMenuFixture.drain

    report["submenu"] = ContextMenuFixture.track(handle, window, labels: ["Rename"],
      hmenu: windows ? submenu.hpopupmenu : nil) do
      ContextMenuFixture.on_main(handle) do
        window.popup_menu(submenu)
        ContextMenuFixture::LOG << "submenu returned"
      end
    end
    sleep 0.3
    report["submenu_log"] = ContextMenuFixture.drain
    report["scale_factor"] = window.scale_factor
    puts "REPORT #{JSON.generate(report)}"
    handle.exit(0)
  rescue => e
    puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(8))}"
    handle.exit(1)
  end
end
