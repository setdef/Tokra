# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#!/usr/bin/env ruby
# Tokra Rails Runner - Direct, no middleware

require_relative "../../lib/tokra"

ENV["RAILS_ENV"] = "production"
require_relative "config/environment"

require "logger"

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO
LOGGER.progname = "TokraRails"
LOGGER.formatter = proc do |severity, datetime, progname, msg|
  timestamp = datetime.strftime("%H:%M:%S.%L")
  "#{timestamp} [#{severity.ljust(5)}] #{progname}: #{msg}\n"
end

LOGGER.info { "=" * 60 }
LOGGER.info { "Tokra Rails - Direct (No Middleware)" }
LOGGER.info { "=" * 60 }
LOGGER.info { "Ruby #{RUBY_VERSION} | Rails #{Rails::VERSION::STRING} | Tokra #{Tokra::VERSION}" }
LOGGER.info { "Starting Rails application..." }

Rack::Handler::Tokra.run(
  Rails.application,
  title: "Tokra Tasks",
  width: 900.0,
  height: 700.0,
  # invoke_handler receives an Invoke and resolves the frontend promise.
  # Must be Ractor-shareable, so it captures nothing.
  invoke_handler: Ractor.shareable_proc { |invoke|
    invoke.resolve("ack:#{invoke.command}")
    true
  }
)

LOGGER.info { "Goodbye!" }
