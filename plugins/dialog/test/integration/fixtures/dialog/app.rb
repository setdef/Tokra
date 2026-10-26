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
# The page tells the plugin:answer|next command how the next dialog should
# end. On macOS a thread finds the sheet on the main window and ends it
# through AppKit with OK or Cancel, as the user's click would. On Linux
# the dialogs run a fake zenity (test_dialog_window.rb puts it on PATH),
# which answers from files this command writes.

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
    def self.open?
      !sheet.nil?
    end

    # Ends the sheet with NSModalResponseOK (1) or Cancel (0); +false+
    # when no sheet is open yet. -[NSSavePanel ok:] is not implemented for
    # the out-of-process panels of recent macOS, so this ends the sheet as
    # its window would.
    def self.finish(accept)
      window, sheet = self.sheet
      return false unless window

      @end.call(window, @sel.call("endSheet:returnCode:"), sheet, accept ? 1 : 0)
      true
    end
  end

  # Serves plugin:answer|next, which arranges how the next dialog ends, and
  # plugin:answer|zenity, which reads the arguments the fake zenity got.
  class Plugin < Tokra::Plugin
    def name
      "answer"
    end

    def initialize(app, config = {})
      super
      @pending = Thread::Queue.new
      start_sheet_thread(app) if RUBY_PLATFORM.include?("darwin")
    end

    def extend_api(invoke)
      case invoke.command
      when "next" then invoke.resolve(arrange(invoke.payload))
      when "zenity" then invoke.resolve(File.exist?(log) ? File.read(log).lines(chomp: true) : nil)
      when "ping" then invoke.resolve("pong")
      when "open" then invoke.resolve(dialog_open?)
      else return false
      end
      true
    end

    private def arrange(payload)
      accept = payload["accept"]
      if RUBY_PLATFORM.include?("darwin")
        @pending << [accept, payload.fetch("delay", 0)]
      else
        zenity = ENV.fetch("FAKE_ZENITY_DIR")
        FileUtils.rm_f(log)
        File.write(File.join(zenity, "output"), payload.fetch("output", ""))
        File.write(File.join(zenity, "status"), accept ? "0" : "1")
        File.write(File.join(zenity, "delay"), payload.fetch("delay", 0).to_s)
      end
      nil
    end

    # Whether a dialog is open now: a sheet on macOS, or the fake zenity
    # having started on Linux. Runs on the main thread, as invokes do.
    private def dialog_open?
      RUBY_PLATFORM.include?("darwin") ? Sheet.open? : File.exist?(log)
    end

    private def log
      File.join(ENV.fetch("FAKE_ZENITY_DIR", DIR), "log")
    end

    # Waits for each arranged ending, then +delay+ seconds more, and polls
    # the main thread until a sheet is open to end. Each ending ends one
    # sheet, however many polls are still queued.
    private def start_sheet_thread(app)
      Sheet.load
      pending = @pending
      Thread.new do
        loop do
          accept, delay = pending.pop
          sleep 0.2 + delay
          finished = Thread::Queue.new
          done = false
          until finished.pop(timeout: 0.2)
            app.run_on_main_thread do
              next if done

              done = Sheet.finish(accept)
              finished << true if done
            end
          end
        end
      end
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
FixtureApp.builder(FixtureApp::Site.new(__dir__, options, DialogFixture::ROUTES), "dialog",
  plugins: [Tokra::Plugins::Dialog::Plugin, DialogFixture::Plugin])
  .with_global_tauri
  .run
