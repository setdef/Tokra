# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for keyboard/tray_menu_test.rb: a real tray menu, opened the way
# tray-icon opens it for a click (plan 043), on macOS and Windows.
#
# On macOS a platform timer on the main thread, outside tao's handler as
# a click would be, opens the tray's menu (PlatformTray.open_menu) while
# keeping the GVL, as the main thread holds it when a click reaches tao's
# loop; on Windows the click's message is posted, and tao's loop delivers
# it to tray-icon's window as the shell's would be.
# While the menu tracks, another timer finds it and reads its items, and a
# second Ruby thread, which runs only if something lets go of the GVL,
# sees the ticker tick once and then closes the menu: on macOS by choosing an item
# (-[NSMenu performActionForItemAtIndex:]) and cancelling
# (-[NSMenu cancelTracking]) through GCD's main queue, on Windows by
# posting WM_CANCELMODE and then the chosen item's WM_COMMAND. A fallback
# timer closes a menu that thread never reached. It prints REPORT <json>
# and exits.
#
# Linux's tray menu belongs to the desktop's StatusNotifierItem host,
# which shows it over D-Bus; with no host, nothing in this process can
# open it, so the fixture reports that and exits.
#
#   bundle exec ruby test/integration/fixtures/tray_menu/app.rb

require_relative "../../support/fixture_app"
require_relative "../../support/platform_popup"
require_relative "../../support/platform_tray"

$stdout.sync = true

module TrayMenuFixture
  # Prints a progress line, so a hang shows how far the fixture got.
  def self.progress(stage)
    puts "PROGRESS #{stage}"
  end

  # What the listeners and the main thread did, in order.
  LOG = Thread::Queue.new
  LABELS = %w[Show Hide].freeze

  # Runs the block on the main thread and waits for its answer.
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

  # The log until it holds every entry of +wanted+, or five seconds pass.
  def self.until_logged(wanted)
    seen = []
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until (wanted - seen).empty?
      left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if left <= 0

      entry = LOG.pop(timeout: left)
      seen << entry if entry
    end
    seen
  end

  # Closes +menu+, choosing the first item unless +choose+ is false.
  def self.close(menu, hmenu, choose:, on_main:)
    case Tokra::Menu.os
    when :macos
      return PlatformPopup::Appkit.cancel(menu) if on_main

      PlatformPopup::Appkit.on_main_queue do
        PlatformPopup::Appkit.activate(menu, LABELS.first) if choose
        PlatformPopup::Appkit.cancel(menu)
      end
    else
      tray_window = PlatformTray::Win32.tray_windows.first
      PlatformPopup::Win32.cancel(tray_window)
      PlatformTray::Win32.choose(hmenu, 0) if choose
    end
  end
end

app = Tokra::Builder.default.title("Tokra integration: tray menu #{Process.pid}").size(320, 240)
  .on_menu_event(&Ractor.shareable_proc { |_handle, event| TrayMenuFixture::LOG << "app:#{event.id}" })
  .on_tray_icon_event(&Ractor.shareable_proc { |_handle, event|
    name = event.class.name.split("::").last
    detail = event.respond_to?(:button_state) ? ":#{event.button.name}:#{event.button_state.name}" : ""
    TrayMenuFixture::LOG << "event:#{name}#{detail}"
  })
  .build
FixtureApp.background(app)

app.run do |handle, event|
  next unless event.is_a?(Tokra::RunEvent::Ready)

  if Tokra::Menu.os == :linux
    puts "REPORT #{JSON.generate('unsupported' => 'the desktop StatusNotifierItem host shows the menu')}"
    handle.exit(0)
    next
  end

  window = handle.get_window("main")
  menu = Tokra::Menu::MenuBuilder.with_id(handle, "tray-menu").text("tray-show", "Show").text("tray-hide", "Hide").build
  Tokra::Tray::TrayIconBuilder.with_id("menu-tray")
    .icon(Tokra::Image.new(rgba: "\x20\x80\xE0\xFF".b * 256, width: 16, height: 16)).menu(menu)
    .on_menu_event { |_handle, heard| TrayMenuFixture::LOG << "tray:#{heard.id}" }
    .build(handle)
  hmenu = (Tokra::Menu.os == :windows) ? menu.hpopupmenu : nil

  Thread.new do
    report = {}
    shown = Thread::Queue.new
    returned = Thread::Queue.new
    dismissed_by = Thread::Queue.new
    done = false
    seen_open = false
    opening = false
    macos = Tokra::Menu.os == :macos
    TrayMenuFixture.progress("setting up")
    TrayMenuFixture.on_main(handle) do
      PlatformPopup::Appkit.observe if macos
      PlatformPopup.every(window, 50) do
        next false if done

        found = PlatformPopup.find(TrayMenuFixture::LABELS)
        if found && !seen_open
          seen_open = true
          report["labels"] = PlatformPopup.labels(found, hmenu)
          shown << found
        elsif !found && seen_open && !macos
          # TrackPopupMenu has returned: the posted click's handling is over.
          done = true
          TrayMenuFixture::LOG << "menu returned"
          returned << true
          next false
        end
        true
      end
      PlatformPopup.every(window, 8000) do
        unless done
          TrayMenuFixture.close(PlatformPopup.find(TrayMenuFixture::LABELS, shown: false), hmenu, choose: false,
            on_main: true)
          dismissed_by << "fallback"
        end
        false
      end
      if macos
        PlatformPopup.every(window, 10) do
          # A timer may fire again while the menu it opened tracks; only the
          # first opens it.
          next false if opening

          opening = true
          report["opened"] = PlatformTray.open_menu
          done = true
          TrayMenuFixture::LOG << "menu returned"
          returned << true
          false
        end
      end
    end
    report["opened"] = PlatformTray.open_menu unless macos
    TrayMenuFixture.progress("opening")

    ticks = 0
    ticker = Thread.new do
      loop do
        ticks += 1
        sleep 0.01
      end
    end
    closer = Thread.new do
      found = shown.pop(timeout: 20)
      next unless found

      TrayMenuFixture.progress("tracking")
      at_shown = ticks
      # Running at all proves the GVL was let go while the menu tracks;
      # one tick of the other thread shows it too, by order, not by rate.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      Thread.pass until ticks > at_shown || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      report["ticks_while_tracking"] = ticks - at_shown
      TrayMenuFixture.close(found, hmenu, choose: true, on_main: false)
      dismissed_by << "thread"
    end

    returned.pop(timeout: 30)
    TrayMenuFixture.progress("closed")
    closer.join(5)
    ticker.kill
    report["dismissed_by"] = dismissed_by.pop(timeout: 1)
    report["log"] = TrayMenuFixture.until_logged(["menu returned", "app:tray-show", "tray:tray-show"])
    puts "REPORT #{JSON.generate(report)}"
    handle.exit(0)
  rescue => e
    puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(8))}"
    handle.exit(1)
  end
end
