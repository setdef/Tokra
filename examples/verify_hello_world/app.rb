# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# !/usr/bin/env ruby

# Hello World Example - Serve static index.html via tokra:// protocol
#
# This demonstrates that new_with_protocol works for simple static sites,
# not just complex Rack-style apps. Just like Tauri's WebviewUrl::App("index.html").

require_relative "../../lib/tokra"
require "logger"

# =============================================================================
# Logging Setup
# =============================================================================

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::DEBUG
LOGGER.progname = "HelloWorld"
LOGGER.formatter = proc do |severity, datetime, progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  "#{timestamp} [#{severity.ljust(5)}] #{progname}: #{msg}\n"
end

# Read the static HTML file
html_path = File.expand_path("index.html", __dir__)
html_content = File.read(html_path)

LOGGER.info { "=" * 50 }
LOGGER.info { "Tokra Hello World" }
LOGGER.info { "=" * 50 }
LOGGER.debug { "Ruby version: #{RUBY_VERSION}" }
LOGGER.debug { "Tokra version: #{Tokra::VERSION}" }
LOGGER.info { "Serving: #{html_path}" }
LOGGER.debug { "HTML content length: #{html_content.bytesize} bytes" }

# Create the event loop and window
LOGGER.debug { "Creating EventLoop" }
event_loop = Tokra::Native::EventLoop.new

LOGGER.debug { "Creating Proxy" }
proxy = event_loop.create_proxy

LOGGER.debug { "Creating Window" }
window = Tokra::Native::Window.new(event_loop)
window.set_title("Hello, Tokra!")
window.set_size(600.0, 400.0)
LOGGER.info { "Window created: 600x400, title='Hello, Tokra!'" }

# Create WebView - navigates to tokra://localhost/
LOGGER.debug { "Creating WebView with tokra:// protocol" }
Tokra::Native::WebView.new_with_protocol(window, proxy)
LOGGER.info { "WebView created, navigating to tokra://localhost/" }

LOGGER.info { "-" * 50 }
LOGGER.info { "Event loop starting..." }

request_count = 0
page_load_count = 0

event_loop.run(
  lambda { |event|
    case event
    when Tokra::Native::HttpRequestEvent
      request_count += 1
      request_id = event.request_id
      method = event.method
      uri = event.uri

      LOGGER.info { "HTTP #{method} #{uri}" }
      LOGGER.debug { "Request ##{request_count}, ID=#{request_id}" }

      if method == "GET"
        proxy.respond(
          request_id,
          200,
          [["Content-Type", "text/html; charset=utf-8"]],
          html_content
        )
        LOGGER.debug { "Responded with 200 OK, #{html_content.bytesize} bytes" }
      else
        proxy.respond(
          request_id,
          405,
          [["Content-Type", "text/plain"]],
          "Method Not Allowed"
        )
        LOGGER.debug { "Responded with 405 Method Not Allowed" }
      end

    when Tokra::Native::PageLoadEvent
      page_load_count += 1
      if event.started?
        LOGGER.info { "Page load started: #{event.url}" }
      else
        LOGGER.info { "Page load finished: #{event.url}" }
      end
      LOGGER.debug { "Page load event ##{page_load_count}" }

    when Tokra::Native::WindowCloseEvent
      LOGGER.info { "-" * 50 }
      LOGGER.info { "Window close requested" }
      LOGGER.info { "Session stats: #{request_count} requests, #{page_load_count} page loads" }
      LOGGER.info { "Goodbye!" }
    end
  }
)

LOGGER.info { "Event loop exited" }
