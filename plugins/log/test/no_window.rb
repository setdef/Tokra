# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tokra"

# Stands in for tao and wry: the loop delivers nothing but its end.
module NoWindow
  # The user's local data directory: the temporary directory the test
  # runs the app in, so the window's webview keeps its data there.
  def self.data_local_dir = Dir.pwd

  class Proxy
    def respond(*) = nil
  end

  class EventLoop
    def initialize(_app_id) = nil
    def create_proxy = Proxy.new
    def run(callback) = callback.call(Tokra::Native::LoopDestroyedEvent.new)
  end

  class Window
    def self.empty(_proxy) = new
    def open(*) = nil
    def set_title(_title) = nil
    def set_size(_width, _height) = nil
  end

  class WebView
    def self.empty(_proxy) = new
    def open(*) = nil
    def eval(_script) = nil
  end

  # The real menu classes, which need no window (plan 042).
  Menu = Tokra::Native::Menu
  Submenu = Tokra::Native::Submenu
  MenuItem = Tokra::Native::MenuItem
  CheckMenuItem = Tokra::Native::CheckMenuItem
  PredefinedMenuItem = Tokra::Native::PredefinedMenuItem
  IconMenuItem = Tokra::Native::IconMenuItem
  MenuIcon = Tokra::Native::MenuIcon
end
