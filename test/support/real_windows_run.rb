# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The tripwire behind the real-window tests' routing (Plan 056).
#
# Rake decides from each file's text which tests open real windows, and
# runs only those in test:keyboard, test:real_windows,
# test:real_windows:plugins, and test:console, which set
# TOKRA_REAL_WINDOWS_RUN=1 for the test process. Whatever opens a real
# window or a real system panel, or writes the system clipboard, calls
# RealWindowsRun.require! first, so a test the file rule missed fails, in
# whatever run reached it, instead of opening a window there.
#
# === Example
#
#   RealWindowsRun.require!("RealApp.launch")
module RealWindowsRun
  # The variable the real-window tasks set.
  VARIABLE = "TOKRA_REAL_WINDOWS_RUN"

  # Raised where a real window would open outside a real-window run.
  class Outside < StandardError; end

  # Returns unless this process runs in a real-window task; else raises
  # Outside, naming +what+ would have opened a window.
  def self.require!(what, env = ENV)
    return if env[VARIABLE] == "1"

    raise Outside, "#{what} opens real windows, so it runs only in test:keyboard, test:real_windows, " \
      "test:real_windows:plugins, or test:console (#{VARIABLE}=1). Move its test where tasks/real_windows.rb " \
      "finds it (Plan 056)."
  end
end
