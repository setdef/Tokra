# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "desktop_input_lock"

# Keeps tests that take a Mac's keyboard and mouse out of each other's
# way, and tells the person at the Mac, by banner and aloud, when to step
# away and when to come back.
#
# The lock, the marker, and the spoken notices are the desktop_input_lock
# gem's, which every project sharing the Mac uses (Plan 046). This module
# only decides where Tokra takes the lock (macOS outside CI) and adds
# TOKRA_QUIET to the gem's DESKTOP_INPUT_QUIET.
#
# === Example
#
#   # A rake task that runs, in child processes that must not take the
#   # lock themselves, tests a person's click could fail.
#   KeyboardNotice.taking_the_keyboard { Rake::Task["test:console:core"].invoke }
#
#   # A Minitest test that takes the keyboard: the span lasts the run.
#   KeyboardNotice.take_the_keyboard_for_the_run
#   RealApp.launch("context_menu")
module KeyboardNotice
  class << self
    # Runs the block holding the shared lock, where #locks?, and returns
    # its value. It speaks only where #speaks?, and never with
    # <tt>speak: false</tt>.
    def taking_the_keyboard(speak: true, &)
      return yield unless locks?

      DesktopInputLock.hold(speak: speak && !ENV["TOKRA_QUIET"], &)
    end

    # Takes the shared lock, where #locks?, from this call until the process
    # ends, for a test run whose tests take the keyboard. It speaks only
    # where #speaks?, and in effect only at the first call: spans in one
    # process nest, and a later one finds the marker naming this process,
    # so it says nothing. The person hears one step-away and one come-back
    # however many tests take the keyboard and however long the run takes
    # between them. Returns +nil+.
    #
    # Each span ends in an at_exit registered after the gem's own, so it
    # runs first, and the gem then finds the lock free and calls the person
    # back. Minitest.after_run would run too late: Minitest registers it
    # before the tests run, so the gem would find its own process still
    # holding the lock and leave the person away. The order matters only
    # for a speaking span: a quiet one gets no hook from the gem, and its
    # lock goes when the process does.
    #
    # === Example
    #
    #   def setup
    #     KeyboardNotice.take_the_keyboard_for_the_run
    #     @run = RealApp.launch("context_menu")
    #   end
    def take_the_keyboard_for_the_run
      return unless locks?

      held = DesktopInputLock.acquire(speak: !ENV["TOKRA_QUIET"])
      at_exit { held.release }
      nil
    end

    # Whether tests on this machine may collide with another project's over
    # the keyboard: macOS, not CI.
    def locks?
      RbConfig::CONFIG["host_os"].include?("darwin") && !ENV["CI"]
    end

    # Whether this machine is one a person may be typing at: it locks, the
    # gem would speak, and TOKRA_QUIET is not set.
    def speaks?
      locks? && !ENV["TOKRA_QUIET"] && DesktopInputLock::DEFAULT.speaks?
    end
  end
end
