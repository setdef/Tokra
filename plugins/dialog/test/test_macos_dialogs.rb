# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/dialog_test"

# The file commands on macOS, end to end, without a window.
#
# Each runs in a child whose test thread plays the event loop for
# RuntimeContext. With no application running, rfd's async dialog falls
# back to a modal dialog on the main thread (rfd 0.17.2
# src/backend/macos/modal_future.rs:104-119), so the command's main-thread
# start runs the real AppKit panel there. Another thread asks AppKit to run
# -[NSApplication abortModal] on the main thread, the technique ferro-rfd's
# tests use, and the panel closes as if cancelled. The answer still has to
# cross the plugin's whole path: worker thread, main-thread start, the
# thread that waits on rfd's future, and the invoke.
#
# Message dialogs without a parent window are system alerts on a thread of
# rfd's own (utils/user_alert.rs:177-196), which only a person can dismiss,
# so none opens here.
class TestMacosDialogs < Minitest::Test
  include DialogTest

  # Sends abortModal to the main thread every quarter second until the
  # block's flag is set.
  APPKIT = <<~RUBY
    require "fiddle"
    module AppKit
      OBJC = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
      KIT = Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")
      SEL = Fiddle::Function.new(OBJC["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      SEND = Fiddle::Function.new(OBJC["objc_msgSend"],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_CHAR],
        Fiddle::TYPE_VOIDP)

      def self.abort_modal_until(done)
        Thread.new do
          sends = 0
          until done.call
            sleep 0.25
            app = Fiddle::Pointer.new(KIT["NSApp"]).ptr
            next if app.null?

            SEND.call(app, SEL.call("performSelectorOnMainThread:withObject:waitUntilDone:"),
              SEL.call("abortModal"), nil, 0)
            sends += 1
          end
          sends
        end
      end
    end
  RUBY

  def setup
    skip_unless_platform(:macos)
  end

  private def cancelled(command, payload)
    (answer, sends), errors = in_child(<<~RUBY)
      #{APPKIT}
      #{CHILD_COMMAND}
      done = false
      aborter = AppKit.abort_modal_until(-> { done })
      answer = run_command(#{command.dump}, #{payload.inspect})
      done = true
      [answer, aborter.value]
    RUBY
    assert_operator sends, :>=, 1, "the panel closed before anything aborted it"
    assert_includes errors, "I will fallback to sync dialog for you."
    answer
  end

  def test_a_cancelled_open_resolves_null
    assert_equal [true, nil], cancelled("open", { "options" => { "title" => "tokra-dialog test: this closes itself" } })
  end

  def test_a_cancelled_folder_pick_resolves_null
    assert_equal [true, nil], cancelled("open", { "options" => { "directory" => true, "multiple" => true } })
  end

  def test_a_cancelled_save_resolves_null
    assert_equal [true, nil], cancelled("save", { "options" => { "defaultPath" => Dir.tmpdir } })
  end

  # The Ruby API's block form, called on the main thread: it returns nil
  # and yields the answer, nil when cancelled, on another thread
  # (lib.rs:510-532).
  def test_a_cancelled_pick_file_block_yields_nil
    (returned, answer, thread), = in_child(<<~RUBY)
      #{APPKIT}
      app = Tokra::Builder.default.build(native: StubNative)
      handle = app.handle
      handle.plugin(Tokra::Plugins::Dialog::Plugin.new(handle))
      answers = Thread::Queue.new
      done = false
      aborter = AppKit.abort_modal_until(-> { done })
      returned = handle.dialog.file.pick_file { |path| answers << [path, Thread.current == Thread.main] }
      done = true
      aborter.value
      answer, on_main = answers.pop
      [returned, answer, on_main]
    RUBY

    assert_nil returned
    assert_nil answer
    refute thread, "the block should run off the main thread"
  end
end
