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
# of the GVL, sees a ticker thread tick once and then closes the menu: on
# macOS by choosing an item of the first
# (-[NSMenu performActionForItemAtIndex:], sent through GCD's main queue)
# and cancelling each (-[NSMenu cancelTracking]), on Linux by choosing an
# item of the first (gtk_menu_shell_activate_item) and cancelling the
# second. On Windows that thread asks, and the main thread's timer, which
# the menu's modal loop runs, ends the menu with EndMenu (plan 051). A
# fallback timer closes a menu that thread never reached, which a popup
# holding the GVL would cause, and the report names whichever closed it.
# Each stage prints PROGRESS <stage> <seconds>, so a hang shows how far
# it got. It prints REPORT <json> and exits.
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

  # Shows the context menu +name+ with +show+, which returns once it
  # closes, and reports what happened while it tracked. +labels+ are the
  # items the platform should hold; +choose+ is the item to choose on
  # macOS and Linux, or +nil+ to cancel.
  def self.track(handle, window, name:, labels:, choose: nil, hmenu: nil, &show)
    shown = Thread::Queue.new
    seen = {}
    done = false
    found = false
    # Set by the fallback when it fires while the menu tracks, and by the
    # closer thread once it has closed the menu or, on Windows, asked the
    # main thread to.
    fell_back = false
    closer_closed = false
    close_asked = false
    windows = Tokra::Menu.os == :windows
    # Read before the popup: the handle is a getter the main thread
    # answers, and the main thread is busy while a menu tracks.
    place = (Tokra::Menu.os == :macos) ? [window.inner_position, window.scale_factor] : nil
    on_main(handle) do
      PlatformPopup::Appkit.observe if Tokra::Menu.os == :macos
      PlatformPopup.every(window, 50) do
        next false if done

        unless found
          menu = PlatformPopup.find(labels)
          next true unless menu

          found = true
          seen["labels"] = PlatformPopup.labels(menu, hmenu)
          seen["offset"] = PlatformPopup.offset(window, menu, TITLE, place)
          FixtureApp.progress("#{name}:shown")
          shown << menu
          # On Windows this timer stays, to end the menu when asked.
          next windows
        end
        next true unless close_asked

        # The menu may have closed some other way, such as the app losing
        # the foreground; then there is nothing to end.
        if PlatformPopup.find(labels)
          close(nil, nil, on_main: true)
          FixtureApp.progress("#{name}:cancel-posted")
        end
        false
      end
      PlatformPopup.every(window, 8000) do
        unless done
          fell_back = true
          FixtureApp.progress("#{name}:fallback-fired")
          close(PlatformPopup.find(labels, shown: false), nil, on_main: true)
        end
        false
      end
      FixtureApp.progress("#{name}:timers-set")
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
      # Running at all proves the popup let go of the GVL; one tick of the
      # other thread shows it too, by order rather than by rate, which a
      # loaded machine cannot meet on time.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      Thread.pass until ticks > at_shown || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      seen["ticks_while_tracking"] = ticks - at_shown
      if windows
        close_asked = true
        FixtureApp.progress("#{name}:close-asked")
      else
        close(menu, choose, on_main: false)
        FixtureApp.progress("#{name}:cancel-posted")
      end
      closer_closed = true
    end

    FixtureApp.progress("#{name}:popup-called")
    show.call
    done = true
    FixtureApp.progress("#{name}:returned")
    closer.join(5)
    ticker.kill
    # A popup returns only once something closes it: the fallback, if it
    # fired first, or else the closer thread.
    seen.merge("dismissed_by" => if fell_back then "fallback" elsif closer_closed then "thread" end)
  end

  # Closes +menu+: on macOS chooses +choose+, if given, and cancels,
  # through AppKit on the main thread; chooses +choose+ or cancels on
  # Linux, through GTK on the main thread; on Windows ends the menu with
  # EndMenu, which only the main thread, whose menu it is, may call.
  def self.close(menu, choose, on_main:)
    case Tokra::Menu.os
    when :macos then close_appkit(menu, choose, on_main:)
    when :windows then PlatformPopup::Win32.end_menu
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

  FixtureApp.progress("ready")
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
    FixtureApp.progress("menus-built")

    report["menu"] = ContextMenuFixture.track(handle, window, name: "menu", labels: ["Copy Link", "Open"], choose: "Copy Link",
      hmenu: windows ? menu.hpopupmenu : nil) do
      report["menu_answer"] = menu.popup_at(window, Tokra::LogicalPosition.new(x: 30, y: 40))
      ContextMenuFixture::LOG << "menu returned"
    end
    sleep 0.3
    report["menu_log"] = ContextMenuFixture.drain

    report["submenu"] = ContextMenuFixture.track(handle, window, name: "submenu", labels: ["Rename"],
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
