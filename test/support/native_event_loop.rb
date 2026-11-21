# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fiddle"
require "minitest"
require "rbconfig"
require_relative "real_windows_run"

# The one Native::EventLoop the in-process tests share.
#
# On Linux, tao registers a GtkApplication on the session bus for each event
# loop (tao platform_impl/linux/event_loop.rs:227-230), and a second one in
# the same process fails with "An object is already exported for the
# interface org.gtk.Application", which tao turns into a panic. An app has
# one loop for its whole life, so the tests that only build windows and
# proxies share one too. None of them runs it.
#
# So on Windows nothing ever takes the messages sent to the windows those
# tests build: the test process's main thread runs tests, and later waits
# for the fixtures RealApp launches, without pumping. A webview left open
# there hangs a later fixture. When the fixture's last window goes,
# Windows hands activation and focus to the window that holds the open
# webview, and the fixture's DestroyWindow waits until the test process's
# main thread takes WM_ACTIVATE, WM_SETFOCUS, and the IME's messages for
# it, which it never does (multiwindow_routing hung so, last line
# "EVENT main Tokra::WindowEvent::CloseRequested"). So every test that
# opens a webview closes it, and on Windows LeavesNoWebviewOpen fails the
# test that does not.
module NativeEventLoop
  # Why no event loop can be built here, or +nil+ when it can. Only Linux
  # needs a display server for one; macOS and Windows build it anywhere,
  # including on CI runners.
  def self.unavailable_reason
    return unless RbConfig::CONFIG["host_os"].include?("linux")
    return if [ENV["DISPLAY"], ENV["WAYLAND_DISPLAY"]].any? { |value| value && !value.empty? }

    "no display server (DISPLAY and WAYLAND_DISPLAY are unset or empty)"
  end

  # The shared loop, built on first use on the main thread.
  def self.shared
    @shared ||= begin
      RealWindowsRun.require!("NativeEventLoop.shared")
      Tokra::Native::EventLoop.new(nil)
    end
  end

  # Whether the shared loop has been built in this process.
  def self.built?
    !@shared.nil?
  end

  # The handles of the WebView2 webviews open in this process: each
  # window of class WebView2Hosts::HOST under one of this process's
  # top-level windows. Empty off Windows.
  def self.open_webviews
    return [] unless RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)

    WebView2Hosts.under(::Process.pid)
  end

  # Fails, after its teardown, a test that leaves a webview open in a
  # process that built the shared loop, naming each one once, so the test
  # that opened it fails and not every test after it.
  module LeavesNoWebviewOpen
    # The webviews already reported.
    REPORTED = Set.new

    def after_teardown
      super
      return unless NativeEventLoop.built?

      left = NativeEventLoop.open_webviews.reject { |host| REPORTED.include?(host) }
      return if left.empty?

      REPORTED.merge(left)
      flunk "#{name} left #{left.size} webview(s) open; on Windows a fixture launched later from this process " \
        "hangs handing activation to it (test/support/native_event_loop.rb). Close each webview the test opens."
    end
  end

  # Finds WebView2's windows through user32.
  module WebView2Hosts
    # The class of the window WebView2 makes inside the window it hosts a
    # webview in, on the host's thread: Chromium's widget class, the
    # "Chrome_WidgetWin_0" HangProbe lists under each fixture window, and
    # the window the activation in the hang above ends on. Its controller's
    # Close destroys it (ICoreWebView2Controller::Close).
    HOST = "Chrome_WidgetWin_0"

    # Each HOST window under a top-level window of process +pid+.
    def self.under(pid)
      top_level(pid).flat_map { |window| children(window) }.select { |child| class_name(child) == HOST }
    end

    def self.top_level(pid)
      found = []
      enumerate("EnumWindows") { |window| found << window if process(window) == pid }
      found
    end

    def self.children(window)
      found = []
      enumerate("EnumChildWindows", window) { |child| found << child }
      found
    end

    # Calls user32's +function+ with +before+ and a callback that yields
    # each window it is given and goes on.
    def self.enumerate(function, *before)
      visit = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T]) do |window, _|
        yield window
        1
      end
      arguments = [*before.map { Fiddle::TYPE_INTPTR_T }, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T]
      fn(function, arguments, Fiddle::TYPE_INT).call(*before, visit, 0)
    end

    def self.process(window)
      pid = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
      fn("GetWindowThreadProcessId", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT).call(window, pid)
      pid[0, 4].unpack1("L")
    end

    def self.class_name(window)
      buffer = Fiddle::Pointer.malloc(256 * 2, Fiddle::RUBY_FREE)
      length = fn("GetClassNameW", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        .call(window, buffer, 256)
      buffer.to_str(length * 2).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
    end

    def self.fn(name, arguments, result)
      @user32 ||= Fiddle.dlopen("user32")
      Fiddle::Function.new(@user32[name], arguments, result)
    end
  end
end

Minitest::Test.prepend(NativeEventLoop::LeavesNoWebviewOpen)
