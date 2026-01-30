# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# !/usr/bin/env ruby

# Basic smoke test for Tokra native extension

require_relative "lib/tokra"

puts "Tokra v#{Tokra::VERSION}"
puts "Testing native extension load..."

# Test that the module and classes are defined
raise "Missing Tokra::Native" unless defined?(Tokra::Native)
raise "Missing EventLoop" unless defined?(Tokra::Native::EventLoop)
raise "Missing Window" unless defined?(Tokra::Native::Window)
raise "Missing WebView" unless defined?(Tokra::Native::WebView)
raise "Missing Proxy" unless defined?(Tokra::Native::Proxy)
raise "Missing IpcEvent" unless defined?(Tokra::Native::IpcEvent)
raise "Missing WakeUpEvent" unless defined?(Tokra::Native::WakeUpEvent)
raise "Missing WindowCloseEvent" unless defined?(Tokra::Native::WindowCloseEvent)

puts "✓ Native extension loaded successfully!"
puts ""
puts "Available classes:"
puts "  Tokra::Native::EventLoop"
puts "  Tokra::Native::Window"
puts "  Tokra::Native::WebView"
puts "  Tokra::Native::Proxy"
puts "  Tokra::Native::IpcEvent"
puts "  Tokra::Native::WakeUpEvent"
puts "  Tokra::Native::WindowCloseEvent"
