# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# :nodoc: all

# !/usr/bin/env ruby

# Ping-Pong Verification Example - Real Roda App
#
# This demonstrates Tokra's Rack adapter with Roda: a real Roda application
# running via the tokra:// custom protocol, just like Tauri's tauri://.

require_relative "../../lib/tokra"
require "roda"
require "json"
require "uri"
require "stringio"
require "securerandom"
require "logger"

# =============================================================================
# Logging Setup
# =============================================================================

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::DEBUG
LOGGER.progname = "PingPong"
LOGGER.formatter = proc do |severity, datetime, progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  "#{timestamp} [#{severity.ljust(5)}] #{progname}: #{msg}\n"
end

MESSAGE = ARGV[0] || "Default message - pass an argument!" # :nodoc:

LOGGER.info { "Starting Ping-Pong verification example" }
LOGGER.debug { "Ruby version: #{RUBY_VERSION}" }
LOGGER.debug { "Tokra version: #{Tokra::VERSION}" }
LOGGER.debug { "Message argument: #{MESSAGE.inspect}" }

# =============================================================================
# The Roda Application
# =============================================================================

class PingPongApp < Roda
  # Session secret - just needs to be consistent for this process
  plugin :sessions, secret: SecureRandom.hex(32)
  plugin :flash
  plugin :render, views: File.expand_path("views", __dir__), escape: true
  plugin :json
  plugin :all_verbs
  plugin :public, root: File.expand_path("public", __dir__)

  # Store message in opts so it's accessible in route block
  opts[:message] = MESSAGE
  opts[:logger] = LOGGER

  route do |r|
    opts[:logger].debug { "Routing: #{r.request_method} #{r.path}" }

    # Serve static assets from public/
    r.public

    # GET / - serve the main page
    r.root do
      opts[:logger].info { "Serving index page" }
      opts[:logger].debug { "Flash contents: #{flash.inspect}" }
      view("index", locals: { message: opts[:message], flash: })
    end

    # POST /submit - handle form submission, redirect back
    r.post "submit" do
      response = r.params["response"]
      opts[:logger].info { "Form submission received" }
      opts[:logger].debug { "Form response value: #{response.inspect}" }

      flash["success"] = "Form submitted! You said: \"#{response}\""
      opts[:logger].debug { "Flash set, redirecting to root" }

      r.redirect "tokra://localhost/"
    end

    # POST /api - JSON API endpoint
    r.post "api" do
      body = r.body.read
      opts[:logger].info { "API request received" }
      opts[:logger].debug { "API request body: #{body.inspect}" }

      data = begin
        JSON.parse(body)
      rescue
        { "raw" => body }
      end
      opts[:logger].debug { "Parsed API data: #{data.inspect}" }

      response = {
        status: "ok",
        received: data,
        timestamp: Time.now.iso8601,
      }
      opts[:logger].debug { "API response: #{response.inspect}" }

      response
    end
  end
end

LOGGER.info { "Roda application class defined" }
LOGGER.debug { "Plugins loaded: sessions, flash, render, json, all_verbs" }

# =============================================================================
# Run the app
# =============================================================================

LOGGER.info { "=" * 50 }
LOGGER.info { "Tokra Ping-Pong (Roda App)" }
LOGGER.info { "=" * 50 }

LOGGER.debug { "Freezing Roda app" }
rack_app = PingPongApp.freeze.app
LOGGER.info { "Starting Rack::Handler::Tokra.run" }

Rack::Handler::Tokra.run(
  rack_app,
  title: "Tokra Ping-Pong",
  width: 500,
  height: 600,
  # This acts like Tauri's invoke_handler, receiving IPC messages
  invoke_handler: proc { |msg| LOGGER.info("Sent via IPC: #{msg}") }
)

LOGGER.info { "Event loop exited" }
