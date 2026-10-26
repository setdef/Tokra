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

module DialogFixture
  # A folder to save into, with its real path, as the dialogs report it.
  DIR = File.realpath(Dir.mktmpdir("tokra-dialog-fixture")).freeze
  File.write(File.join(DIR, "existing.txt"), "")

  # Ends the main window's sheet through AppKit, on the main thread.
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
    end

    # Whether the main window has a sheet open.
    def self.open?
      window = @get.call(@app.ptr, @sel.call("mainWindow"))
      !window.null? && !@get.call(window, @sel.call("attachedSheet")).null?
    end

    # Ends the sheet with NSModalResponseOK (1) or Cancel (0); +false+
    # when no sheet is open yet. -[NSSavePanel ok:] is not implemented for
    # the out-of-process panels of recent macOS, so this ends the sheet as
    # its window would.
    def self.finish(accept)
      window = @get.call(@app.ptr, @sel.call("mainWindow"))
      return false if window.null?

      sheet = @get.call(window, @sel.call("attachedSheet"))
      return false if sheet.null?

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
