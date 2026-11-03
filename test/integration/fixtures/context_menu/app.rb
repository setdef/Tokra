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
# second. On Windows, where the menu's modal loop may stop delivering
# WM_TIMER, that thread finds and reads the menu window itself and ends
# the menu with a WM_CANCELMODE it sends to the owner window (plan 051);
# the main thread's timer only witnesses the menu, and --no-main-timer
# skips it. A fallback timer closes a menu that thread never reached,
# which a popup holding the GVL would cause, and the report names
# whichever closed it. Each stage prints PROGRESS <stage> <seconds>, so a
# hang shows how far it got. It prints REPORT <json> and exits.
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
options = FixtureApp.options(ARGV, :no_main_timer)

module ContextMenuFixture
  TITLE = "Tokra integration: context menu #{Process.pid}".freeze

  # What the main thread and the listeners did, in order.
  LOG = Thread::Queue.new

  # Shows the context menu +name+ with +show+, which returns once it
  # closes, and reports what happened while it tracked. +labels+ are the
  # items the platform should hold; +choose+ is the item to choose on
  # macOS and Linux, or +nil+ to cancel. +main_timer+ false skips the
  # main thread's 50 ms timer on Windows, where the closer thread finds
  # and ends the menu alone.
  def self.track(handle, window, name:, labels:, choose: nil, hmenu: nil, main_timer: true, &show)
    shown = Thread::Queue.new
    seen = {}
    done = false
    # Set by the fallback when it fires while the menu tracks, and by the
    # closer thread once it has closed the menu.
    fell_back = false
    closer_closed = false
    windows = Tokra::Menu.os == :windows
    owner = nil
    main_thread = nil
    # Read before the popup: the handle is a getter the main thread
    # answers, and the main thread is busy while a menu tracks.
    place = (Tokra::Menu.os == :macos) ? [window.inner_position, window.scale_factor] : nil
    on_main(handle) do
      PlatformPopup::Appkit.observe if Tokra::Menu.os == :macos
      if windows
        owner = window.window_handle.hwnd
        main_thread = PlatformPopup::Win32.current_thread
        # Only a witness of whether WM_TIMER reaches the fixture while the
        # menu tracks, which on Windows CI it may not (plan 051).
        if main_timer
          PlatformPopup.every(window, 50) do
            next false if done
            next true unless PlatformPopup::Win32.find(PlatformPopup::Win32.current_thread, hmenu)

            FixtureApp.progress("#{name}:main-timer-saw")
            false
          end
        end
      else
        PlatformPopup.every(window, 50) do
          next false if done

          menu = PlatformPopup.find(labels)
          next true unless menu

          seen["labels"] = PlatformPopup.labels(menu, hmenu)
          seen["offset"] = PlatformPopup.offset(window, menu, TITLE, place)
          FixtureApp.progress("#{name}:shown")
          shown << menu
          false
        end
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

    ticker = PlatformPopup::Ticker.new
    closer = Thread.new do
      menu = windows ? find_win32(main_thread, owner, name, seen, hmenu) : shown.pop(timeout: 20)
      next unless menu

      handle.run_on_main_thread { LOG << "task sent while tracking" }
      # Running at all proves the popup let go of the GVL; one tick of the
      # other thread shows it too, by order rather than by rate, which a
      # loaded machine cannot meet on time.
      seen["ticks_while_tracking"] = ticker.ticks_until_next
      if windows
        closer_closed = cancel_win32(main_thread, owner, hmenu, name)
      else
        close(menu, choose, on_main: false)
        FixtureApp.progress("#{name}:cancel-posted")
        closer_closed = true
      end
    end

    FixtureApp.progress("#{name}:popup-called")
    show.call
    done = true
    FixtureApp.progress("#{name}:returned")
    closer.join(5)
    ticker.stop
    # A popup returns only once something closes it: the fallback, if it
    # fired first, or else the closer thread.
    seen.merge("dismissed_by" => if fell_back then "fallback" elsif closer_closed then "thread" end)
  end

  # Finds +main_thread+'s menu window showing +hmenu+ from the closer
  # thread, so the labels read from +hmenu+ are the window's; records
  # them and its offset from +owner+ in +seen+, and answers it, or
  # +nil+. If it has not shown about 2 s on, prints whether the main
  # thread takes sent messages, which tells a stalled loop from a menu
  # that never opened.
  def self.find_win32(main_thread, owner, name, seen, hmenu)
    menu = PlatformPopup::Win32.await_menu(main_thread, owner, hmenu) do |pumping|
      FixtureApp.progress("#{name}:main-pumping #{pumping}")
    end
    return nil unless menu

    seen["labels"] = PlatformPopup::Win32.labels(hmenu)
    seen["offset"] = PlatformPopup::Win32.offset(owner, menu)
    FixtureApp.progress("#{name}:shown")
    menu
  end

  # Ends the menu from the closer thread with a WM_CANCELMODE sent to
  # +owner+, unless it has already closed some other way, such as the app
  # losing the foreground. Answers whether the main thread took it.
  def self.cancel_win32(main_thread, owner, hmenu, name)
    return false unless PlatformPopup::Win32.find(main_thread, hmenu)

    sent = PlatformPopup::Win32.cancel_mode(owner)
    FixtureApp.progress(sent ? "#{name}:cancel-posted" : "#{name}:cancel-unanswered")
    raised = PlatformPopup::Win32::TIMER_ERRORS.size
    FixtureApp.progress("#{name}:timer-errors #{raised}") if raised.positive?
    sent
  end

  # Closes +menu+: on macOS chooses +choose+, if given, and cancels,
  # through AppKit on the main thread; chooses +choose+ or cancels on
  # Linux, through GTK on the main thread; on Windows, for the fallback,
  # ends the menu with EndMenu, which only the main thread, whose menu it
  # is, may call.
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
      hmenu: windows ? menu.hpopupmenu : nil, main_timer: !options[:no_main_timer]) do
      report["menu_answer"] = menu.popup_at(window, Tokra::LogicalPosition.new(x: 30, y: 40))
      ContextMenuFixture::LOG << "menu returned"
    end
    sleep 0.3
    report["menu_log"] = ContextMenuFixture.drain

    report["submenu"] = ContextMenuFixture.track(handle, window, name: "submenu", labels: ["Rename"],
      hmenu: windows ? submenu.hpopupmenu : nil, main_timer: !options[:no_main_timer]) do
      ContextMenuFixture.on_main(handle) do
        window.popup_menu(submenu)
        ContextMenuFixture::LOG << "submenu returned"
      end
    end
    sleep 0.3
    report["submenu_log"] = ContextMenuFixture.drain
    report["scale_factor"] = window.scale_factor
    report["timer_errors"] = windows ? PlatformPopup::Win32.timer_errors : nil
    puts "REPORT #{JSON.generate(report)}"
    handle.exit(0)
  rescue => e
    puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(8))}"
    handle.exit(1)
  end
end
