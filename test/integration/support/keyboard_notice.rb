# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tells the person at a Mac, aloud, when tests are about to take the
# keyboard and as soon as they have given it back.
#
# Some real-window tests must open a real menu, which tracks the keyboard
# and mouse until it closes, or must bring a fixture to the front. They
# stay reliable only if nobody types into them. Wrapping each in
# KeyboardNotice.taking_the_keyboard says "step away" before the first,
# and "you can come back" once SETTLE seconds pass with none running, so
# a run of such tests is announced once and the person is called back as
# soon as it ends rather than when the whole gate does. It speaks with
# macOS's own +say+ and stays silent on CI, off macOS, without +say+, or
# when TOKRA_QUIET is set.
#
# === Example
#
#   KeyboardNotice.taking_the_keyboard { menu.popup(window) }
module KeyboardNotice
  STEP_AWAY = "Tokra's tests need the keyboard and mouse for a moment. Please step away."
  COME_BACK = "Tokra's tests are done with the keyboard. You can come back now."

  # How long, in seconds, no keyboard-taking test may run before the person
  # is called back. Long enough to bridge the gap between two such tests
  # in a row, short enough that nobody waits on an idle gate.
  SETTLE = 3

  @lock = Mutex.new
  @away = false
  @running = 0
  @last_done = nil
  @caller = nil

  class << self
    # Runs the block, first saying STEP_AWAY unless the person was already
    # told, and returns its value. When the block ends and no other
    # keyboard-taking block starts within SETTLE seconds, says COME_BACK.
    # Speaking blocks until the words are said, so the warning comes
    # before the menu opens. Without a block it only announces.
    def taking_the_keyboard
      return (block_given? ? yield : nil) unless speaks?

      enter
      begin
        block_given? ? yield : nil
      ensure
        leave
      end
    end

    # Whether this machine is one a person may be typing at: macOS, not CI,
    # with +say+, and not silenced by TOKRA_QUIET.
    def speaks?
      RbConfig::CONFIG["host_os"].include?("darwin") && !ENV["CI"] && !ENV["TOKRA_QUIET"] &&
        File.executable?("/usr/bin/say")
    end

    private def enter
      @lock.synchronize do
        @running += 1
        next if @away

        @away = true
        say(STEP_AWAY)
        at_exit { come_back }
        @caller ||= Thread.new { call_back_when_settled }
      end
    end

    private def leave
      @lock.synchronize do
        @running -= 1
        @last_done = Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end
    end

    private def call_back_when_settled
      loop do
        sleep 0.25
        @lock.synchronize do
          next unless @away && @running.zero? && @last_done
          next if Process.clock_gettime(::Process::CLOCK_MONOTONIC) - @last_done < SETTLE

          announce_return
        end
      end
    end

    private def come_back
      @lock.synchronize { announce_return if @away }
    end

    private def announce_return
      @away = false
      say(COME_BACK)
    end

    private def say(words)
      system("/usr/bin/say", words, exception: false)
    end
  end
end
