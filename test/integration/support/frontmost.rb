# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fiddle"

# The process of the app in front on macOS, the one that has the keyboard.
#
# RealApp watches it while a fixture runs, so a fixture that comes to the
# front, and takes the keyboard from the person typing while the suite
# runs, fails its test. It asks the Process Manager (GetFrontProcess and
# GetProcessPID, ApplicationServices), which answers from the window
# server on any thread. NSWorkspace#frontmostApplication would not do: it
# updates only as the main thread's run loop delivers its notifications,
# and running that loop here would also run tao's observers in the tests
# that build native windows in process.
module Frontmost
  SERVICES = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

  # Whether this machine can answer: macOS, while ApplicationServices still
  # has both functions. If Apple removes them, the guard turns off rather
  # than failing every real-window test.
  def self.available?
    return false unless RbConfig::CONFIG["host_os"].include?("darwin")

    functions
    true
  rescue Fiddle::DLError
    false
  end

  # GetFrontProcess and GetProcessPID, each answering an OSErr, a 16-bit
  # status (MacTypes.h).
  def self.functions
    @functions ||= begin
      services = Fiddle.dlopen(SERVICES)
      [
        Fiddle::Function.new(services["GetFrontProcess"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_SHORT),
        Fiddle::Function.new(services["GetProcessPID"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_SHORT),
      ]
    end
  end

  # The pid of the frontmost process, or +nil+ when none is in front.
  def self.pid
    front, pid_of = functions
    serial = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    pid = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    return nil unless front.call(serial).zero? && pid_of.call(serial, pid).zero?

    pid[0, 4].unpack1("l")
  end
end
