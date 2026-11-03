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
# sees the ticker tick once and then closes the menu: on macOS by choosing
# an item (-[NSMenu performActionForItemAtIndex:]) and cancelling
# (-[NSMenu cancelTracking]) through GCD's main queue. On Windows, where
# the menu's modal loop may stop delivering WM_TIMER, that thread finds
# and reads the menu window itself, ends the menu with a WM_CANCELMODE
# it sends to tray-icon's window, posts the chosen item's WM_COMMAND,
# and sees the menu window go (plan 051); the main thread's timer only
# witnesses the menu, and --no-main-timer skips it. A fallback timer
# closes a menu that thread never reached, and the report names
# whichever closed it. Each stage prints PROGRESS <stage> <seconds>, so
# a hang shows how far it got. On Windows the loop's GVL hand-off counts
# are printed as the menu opens, when the closer finds it, and when the
# main timer sees it or the fallback fires, and the report carries them
# (plan 053). With --raise-main the closer, once it finds the Windows
# menu, raises in the main thread instead of closing it, and the report,
# printed once EventLoop#run raises it, says whether the fallback fired.
# It prints REPORT <json> and exits.
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
options = FixtureApp.options(ARGV, :no_main_timer, :raise_main)

module TrayMenuFixture
  # What the closer raises in the main thread with --raise-main. It is not
  # a StandardError, so no callback reports and drops it: it must end the
  # loop (ADR 012, decision 5).
  class MenuRaise < Interrupt; end

  class << self
    # Whether the fallback fired, for the report the main thread prints
    # when the loop raises MenuRaise.
    attr_accessor :fell_back
  end
  self.fell_back = false

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

  # The loop's GVL hand-off counts (plan 053, decision 4), for a progress
  # line: compared at the menu's opening and at the fallback, they say
  # whether the loop cleared, and who handed over, while the menu tracked.
  def self.handoffs
    Tokra::Native::EventLoop.gvl_handoff_counts.map { |name, count| "#{name}=#{count}" }.join(",")
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

  # Finds +main_thread+'s menu window showing +hmenu+ from the closer
  # thread, so the labels read from +hmenu+ are the window's; records
  # them in +report+, and answers it, or +nil+. If it has not shown
  # about 2 s on, prints whether the main thread takes sent messages,
  # which tells a stalled loop from a menu that never opened.
  def self.find_win32(main_thread, owner, hmenu, report)
    menu = PlatformPopup::Win32.await_menu(main_thread, owner, hmenu) do |pumping|
      FixtureApp.progress("tray:main-pumping #{pumping}")
    end
    return nil unless menu

    report["labels"] = PlatformPopup::Win32.labels(hmenu)
    FixtureApp.progress("tray:shown")
    FixtureApp.progress("tray:handoffs #{handoffs}")
    menu
  end

  # Ends the menu from the closer thread with a WM_CANCELMODE sent to
  # +owner+, tray-icon's window, and chooses the first item with a posted
  # WM_COMMAND, unless the menu has already closed some other way, such
  # as the app losing the foreground. Answers whether the main thread
  # took the cancel.
  def self.cancel_win32(main_thread, owner, hmenu)
    return false unless PlatformPopup::Win32.find(main_thread, hmenu)

    sent = PlatformPopup::Win32.cancel_mode(owner)
    PlatformTray::Win32.choose(hmenu, 0) if sent
    FixtureApp.progress(sent ? "tray:cancel-posted" : "tray:cancel-unanswered")
    raised = PlatformPopup::Win32::TIMER_ERRORS.size
    FixtureApp.progress("tray:timer-errors #{raised}") if raised.positive?
    sent
  end

  # Closes +menu+, choosing the first item unless +choose+ is false: on
  # macOS through AppKit, on Windows, for the fallback, with EndMenu,
  # which only the main thread, whose menu it is, may call, and the
  # item's WM_COMMAND.
  def self.close(menu, hmenu, choose:, on_main:)
    case Tokra::Menu.os
    when :macos
      return PlatformPopup::Appkit.cancel(menu) if on_main

      PlatformPopup::Appkit.on_main_queue do
        PlatformPopup::Appkit.activate(menu, LABELS.first) if choose
        PlatformPopup::Appkit.cancel(menu)
      end
    else
      PlatformPopup::Win32.end_menu
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

begin
  app.run do |handle, event|
    next unless event.is_a?(Tokra::RunEvent::Ready)

    if Tokra::Menu.os == :linux
      puts "REPORT #{JSON.generate('unsupported' => 'the desktop StatusNotifierItem host shows the menu')}"
      handle.exit(0)
      next
    end

    FixtureApp.progress("ready")
    window = handle.get_window("main")
    menu = Tokra::Menu::MenuBuilder.with_id(handle, "tray-menu").text("tray-show", "Show").text("tray-hide", "Hide").build
    Tokra::Tray::TrayIconBuilder.with_id("menu-tray")
      .icon(Tokra::Image.new(rgba: "\x20\x80\xE0\xFF".b * 256, width: 16, height: 16)).menu(menu)
      .on_menu_event { |_handle, heard| TrayMenuFixture::LOG << "tray:#{heard.id}" }
      .build(handle)
    hmenu = (Tokra::Menu.os == :windows) ? menu.hpopupmenu : nil
    FixtureApp.progress("menus-built")

    Thread.new do
      report = {}
      shown = Thread::Queue.new
      returned = Thread::Queue.new
      done = false
      opening = false
      # Set by the fallback when it fires while the menu tracks, and by the
      # closer thread once it has closed the menu.
      fell_back = false
      closer_closed = false
      macos = Tokra::Menu.os == :macos
      # On Windows the closer thread finds and ends the menu itself, through
      # tray-icon's window, which owns it, on the main thread, which runs it
      # (plan 051).
      owner = macos ? nil : PlatformTray::Win32.tray_windows.first
      main_thread = nil
      # On Windows, a thread that only sleeps and counts. It advances only
      # when the main thread lets go of the GVL, through Tokra's
      # Thread.pass, a Fiddle call, or IO, so its count beside closer-looks
      # shows whether the main thread ever did while the menu tracked.
      slept = 0
      sleeper = macos ? nil : Thread.new { loop { sleep 0.01; slept += 1 } }
      TrayMenuFixture.on_main(handle) do
        unless macos
          # The thread that runs the menu is the main thread, whose id only
          # it can read; the window's own thread is printed beside it.
          main_thread = PlatformPopup::Win32.current_thread
          window_thread = owner ? PlatformPopup::Win32.thread_of(owner) : 0
          FixtureApp.progress("tray:threads main=#{main_thread} window=#{window_thread}")
        end
        if macos
          PlatformPopup::Appkit.observe
          PlatformPopup.every(window, 50) do
            next false if done

            found = PlatformPopup.find(TrayMenuFixture::LABELS)
            next true unless found

            report["labels"] = PlatformPopup.labels(found, hmenu)
            FixtureApp.progress("tray:shown")
            shown << found
            false
          end
        elsif !options[:no_main_timer]
          # Only a witness of whether WM_TIMER reaches the fixture while the
          # menu tracks, which on Windows CI it may not.
          PlatformPopup.every(window, 50) do
            next false if done
            next true unless PlatformPopup::Win32.find(PlatformPopup::Win32.current_thread, hmenu)

            FixtureApp.progress("tray:main-timer-saw closer-looks=#{PlatformPopup::Win32.looks} tray:sleeper=#{slept} " \
              "tray:handoffs #{TrayMenuFixture.handoffs}")
            false
          end
        end
        PlatformPopup.every(window, 8000) do
          unless done
            fell_back = true
            TrayMenuFixture.fell_back = true
            FixtureApp.progress(macos ? "tray:fallback-fired" : "tray:fallback-fired closer-looks=#{PlatformPopup::Win32.looks} tray:sleeper=#{slept}")
            FixtureApp.progress("tray:handoffs #{TrayMenuFixture.handoffs}") unless macos
            TrayMenuFixture.close(PlatformPopup.find(TrayMenuFixture::LABELS, shown: false), hmenu, choose: false,
              on_main: true)
          end
          false
        end
        if macos
          PlatformPopup.every(window, 10) do
            # A timer may fire again while the menu it opened tracks; only the
            # first opens it.
            next false if opening

            opening = true
            FixtureApp.progress("tray:popup-called")
            report["opened"] = PlatformTray.open_menu
            done = true
            FixtureApp.progress("tray:returned")
            TrayMenuFixture::LOG << "menu returned"
            returned << true
            false
          end
        end
        FixtureApp.progress("tray:timers-set")
      end
      unless macos
        FixtureApp.progress("tray:handoffs #{TrayMenuFixture.handoffs}")
        FixtureApp.progress("tray:popup-called")
        report["opened"] = PlatformTray.open_menu
      end

      ticker = PlatformPopup::Ticker.new
      closer = Thread.new do
        found = macos ? shown.pop(timeout: 20) : TrayMenuFixture.find_win32(main_thread, owner, hmenu, report)
        unless found
          # On Windows nothing else will see the menu go, so say so now
          # rather than wait.
          unless macos
            FixtureApp.progress("tray:never-found")
            returned << false
          end
          next
        end

        # Running at all proves the GVL was let go while the menu tracks;
        # one tick of the other thread shows it too, by order, not by rate.
        report["ticks_while_tracking"] = ticker.ticks_until_next
        if !macos && options[:raise_main]
          # The loop must raise this from EventLoop#run, which means the
          # menu must end without the fallback (plan 053, decision 1).
          FixtureApp.progress("tray:main-raised")
          Thread.main.raise(TrayMenuFixture::MenuRaise, "raised while the menu tracks")
          next
        end
        if macos
          TrayMenuFixture.close(found, hmenu, choose: true, on_main: false)
          FixtureApp.progress("tray:cancel-posted")
          closer_closed = true
        else
          closer_closed = TrayMenuFixture.cancel_win32(main_thread, owner, hmenu)
          # On Windows "returned" means the menu window is gone. That says
          # nothing about whether TrackPopupMenu has returned yet or the
          # posted click was handled, which the log shows on its own.
          gone = PlatformPopup::Win32.await_gone(main_thread, hmenu)
          done = true
          FixtureApp.progress(gone ? "tray:returned" : "tray:gone-timeout")
          TrayMenuFixture::LOG << "menu returned" if gone
          returned << gone
        end
      end

      returned.pop(timeout: 30)
      closer.join(5)
      ticker.stop
      sleeper&.kill
      report["timer_errors"] = macos ? nil : PlatformPopup::Win32.timer_errors
      report["gvl_handoffs"] = Tokra::Native::EventLoop.gvl_handoff_counts
      # The menu closes only once something closes it: the fallback, if it
      # fired first, or else the closer thread.
      report["dismissed_by"] = if fell_back then "fallback" elsif closer_closed then "thread" end
      report["log"] = TrayMenuFixture.until_logged(["menu returned", "app:tray-show", "tray:tray-show"])
      puts "REPORT #{JSON.generate(report)}"
      handle.exit(0)
    rescue => e
      puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(8))}"
      handle.exit(1)
    end
  end
rescue TrayMenuFixture::MenuRaise => e
  # Reached only with --raise-main, once EventLoop#run raised what the
  # closer raised, which it can only do after the menu has ended.
  puts "REPORT #{JSON.generate('raised' => e.message, 'fell_back' => TrayMenuFixture.fell_back,
    'gvl_handoffs' => Tokra::Native::EventLoop.gvl_handoff_counts)}"
  exit 0
end
