# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The one Native::EventLoop the in-process tests share.
#
# On Linux, tao registers a GtkApplication on the session bus for each event
# loop (tao platform_impl/linux/event_loop.rs:227-230), and a second one in
# the same process fails with "An object is already exported for the
# interface org.gtk.Application", which tao turns into a panic. An app has
# one loop for its whole life, so the tests that only build windows and
# proxies share one too. None of them runs it.
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
    @shared ||= Tokra::Native::EventLoop.new
  end
end
