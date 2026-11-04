# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for test_dialog_window.rb: the dialog plugin in a real window,
# called from the page through Tauri's own api-iife.js. Run by hand to
# watch it (the sheets close themselves on macOS):
#
#   cd plugins/dialog && bundle exec ruby test/integration/fixtures/dialog/app.rb --wait
#
# The page tells plugin:answer|next how the next dialog should end, opens
# it, waits until plugin:answer|open sees it, and then asks
# plugin:answer|end to end it. On macOS +end+ finds the sheet on the
# window and ends it through AppKit with OK or Cancel, as the user's click
# would, and prints SHEET_ON <window number>. On Linux the dialogs run a
# fake zenity (test_dialog_window.rb puts it on PATH), which answers from
# files +next+ writes, and waits while +next+ asked it to hold, until
# +end+. On Ready it prints the window's raw handle as WINDOW_HANDLE
# <json>, and on macOS PARENT <json>: rfd's Debug text for a dialog with
# the window as parent, built on the main thread and on another thread.
# Each step prints a PROGRESS line, so a failed run shows where it stopped.

require_relative "../../../../../../test/integration/support/fixture_app"
require "tokra-dialog"
require "tmpdir"
require "fileutils"

# Each line goes out as it is printed, so a run the test kills for hanging
# still shows how far it got. Only here: exit_paths relies on the buffered
# output that Ruby's own exit flushes (Plan 018, decision 4).
$stdout.sync = true

module DialogFixture
  # A folder to save into, with its real path, as the dialogs report it.
  DIR = File.realpath(Dir.mktmpdir("tokra-dialog-fixture")).freeze
  File.write(File.join(DIR, "existing.txt"), "")

  # Ends a window's sheet through AppKit, on the main thread.
  module Sheet
    def self.load
      require "fiddle"
      objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
      kit = Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")
      @app = Fiddle::Pointer.new(kit["NSApp"])
      @sel = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @get = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @end = Fiddle::Function.new(objc["objc_msgSend"],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP)
      @count = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
      @at = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP)
    end

    # The first of the app's windows with a sheet attached, and the sheet,
    # or +nil+. NSApp.windows, not mainWindow: AppKit reports no main
    # window while the app is not active, as under a loaded test run.
    def self.sheet
      windows = @get.call(@app.ptr, @sel.call("windows"))
      @count.call(windows, @sel.call("count")).times do |index|
        window = @at.call(windows, @sel.call("objectAtIndex:"), index)
        sheet = @get.call(window, @sel.call("attachedSheet"))
        return [window, sheet] unless sheet.null?
      end
      nil
    end

    # Whether a window has a sheet open.
    #
    # Follow-up: the sheet sits on a window FixtureApp.keep_in_sight keeps
    # above the others, and unlike that window it takes clicks, so a click
    # meant for the app beneath can end it. Setting the sheet's
    # ignoresMouseEvents, as that method has the window ignore the cursor,
    # would stop that, once it can be shown to work without clicking on the
    # desktop of the person at the Mac.
    def self.open?
      !sheet.nil?
    end

    # Ends the sheet with NSModalResponseOK (1) or Cancel (0) and returns
    # the number of the window it was on; +nil+ when no sheet is open
    # yet. -[NSSavePanel ok:] is not implemented for the out-of-process
    # panels of recent macOS, so this ends the sheet as its window would.
    def self.finish(accept)
      window, sheet = self.sheet
      return nil unless window

      @end.call(window, @sel.call("endSheet:returnCode:"), sheet, accept ? 1 : 0)
      @count.call(window, @sel.call("windowNumber"))
    end
  end

  # Serves plugin:answer|next, which arranges how the next dialog ends;
  # plugin:answer|open, whether it is open; plugin:answer|end, which ends
  # it; and plugin:answer|zenity, which reads the arguments the fake zenity
  # got.
  class Plugin < Tokra::Plugin
    def name
      "answer"
    end

    def initialize(app, config = {})
      super
      @accept = false
      @open = nil
      Sheet.load if RUBY_PLATFORM.include?("darwin")
    end

    # Prints the window's raw handle once the app is ready, so the test
    # can match it against the parent rfd names to the portal. On exit it
    # lets go of a zenity still held, which would otherwise outlive the app.
    def on_event(app, event)
      release if event.is_a?(Tokra::RunEvent::Exit) && !RUBY_PLATFORM.include?("darwin")
      return unless event.is_a?(Tokra::RunEvent::Ready)

      window = app.get_window("main")
      handle = window.window_handle
      puts "WINDOW_HANDLE #{JSON.generate({ 'kind' => handle.class.name.split('::').last, **handle.to_h })}"
      print_parents(app, window) if RUBY_PLATFORM.include?("darwin")
    end

    # Prints what rfd gets as parent, from the main thread and from
    # another, where ferro-rfd looks the window up through the main
    # thread's run loop. The thread is not joined: the main thread has to
    # keep running its loop for that lookup to end.
    private def print_parents(app, window)
      main = app.dialog.file.set_parent(window).to_async_file_dialog.inspect
      Thread.new do
        thread = app.dialog.message("m").parent(window).to_async_message_dialog.inspect
        puts "PARENT #{JSON.generate(main:, thread:)}"
      rescue => e
        puts "PARENT #{JSON.generate(main:, thread: "#{e.class}: #{e.message}")}"
      end
    end

    # Each runs on the main thread, as invokes do, so +open+ and +end+ see
    # the sheet as AppKit has it between events.
    def extend_api(invoke)
      case invoke.command
      when "next" then invoke.resolve(arrange(invoke.payload))
      when "zenity" then invoke.resolve(File.exist?(log) ? File.read(log).lines(chomp: true) : nil)
      when "ping" then invoke.resolve("pong")
      when "open" then invoke.resolve(dialog_open?)
      when "end" then invoke.resolve(finish)
      else return false
      end
      true
    end

    private def arrange(payload)
      @accept = payload["accept"]
      FixtureApp.progress("next accept=#{@accept.inspect} hold=#{payload.fetch('hold', false)}")
      return nil if RUBY_PLATFORM.include?("darwin")

      zenity = ENV.fetch("FAKE_ZENITY_DIR")
      FileUtils.rm_f(log)
      File.write(File.join(zenity, "output"), payload.fetch("output", ""))
      File.write(File.join(zenity, "status"), @accept ? "0" : "1")
      hold = File.join(zenity, "hold")
      payload["hold"] ? FileUtils.touch(hold) : FileUtils.rm_f(hold)
      nil
    end

    # Whether a dialog is open now: a sheet on macOS, or the fake zenity
    # having started on Linux. Prints each change.
    private def dialog_open?
      open = RUBY_PLATFORM.include?("darwin") ? Sheet.open? : File.exist?(log)
      FixtureApp.progress("open #{open}") unless open == @open
      @open = open
    end

    # Ends the open dialog as +next+ arranged, and answers whether it did.
    # On macOS it ends the sheet and answers the number of the window it
    # was on, or +nil+ when no sheet is open. On Linux it lets a held zenity
    # answer, and answers whether one had started and was held.
    private def finish
      ended = if RUBY_PLATFORM.include?("darwin")
        number = Sheet.finish(@accept)
        puts "SHEET_ON #{number}" if number
        number
      else
        File.exist?(log) && release
      end
      FixtureApp.progress("end #{ended.inspect}")
      ended
    end

    # Removes the fake zenity's hold file, and answers whether there was
    # one.
    private def release
      hold = File.join(ENV.fetch("FAKE_ZENITY_DIR"), "hold")
      File.exist?(hold).tap { FileUtils.rm_f(hold) }
    end

    private def log
      File.join(ENV.fetch("FAKE_ZENITY_DIR", DIR), "log")
    end
  end

  # The page's facts: the platform and the folder to save into.
  ROUTES = {
    "/dialog.json" => lambda { |_env|
      platform = RUBY_PLATFORM.include?("darwin") ? "macos" : "linux"
      [200, { "content-type" => "application/json" }, [JSON.generate(platform:, dir: DIR)]]
    },
    "/api-iife.js" => lambda { |_env|
      [200, { "content-type" => "text/javascript" }, [File.read(File.join(__dir__, "api-iife.js"))]]
    },
  }.freeze
end

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options, DialogFixture::ROUTES),
  plugins: [Tokra::Plugins::Dialog::Plugin, DialogFixture::Plugin])
  .run(Tokra.generate_context)
