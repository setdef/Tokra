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
#   KeyboardNotice.taking_the_keyboard { menu.popup(window) }
module KeyboardNotice
  class << self
    # Runs the block holding the shared lock, where #locks?, and returns
    # its value. It speaks only where #speaks?, and never with
    # <tt>speak: false</tt>.
    def taking_the_keyboard(speak: true, &)
      return yield unless locks?

      DesktopInputLock.hold(speak: speak && !ENV["TOKRA_QUIET"], &)
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
