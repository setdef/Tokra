# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#!/usr/bin/env ruby
# Tokra Rails Runner - Direct, no middleware

require_relative "../../lib/tokra"
require "securerandom"

# Rails signs cookies with secret_key_base. A desktop app has no deploy
# step to hand it one, so the app makes its own on first run and keeps it
# in storage/, which git ignores, readable only by you.
# The secret is written whole to a file of its own, then linked into
# place, so the file never exists without it, however two launches race.
unless ENV["SECRET_KEY_BASE"]
  secret_file = File.join(__dir__, "storage", "secret_key_base")
  unless File.exist?(secret_file)
    draft = "#{secret_file}.#{Process.pid}.#{SecureRandom.hex(4)}"
    File.open(draft, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(SecureRandom.hex(64)) }
    begin
      File.link(draft, secret_file)
    rescue Errno::EEXIST
      # Another launch linked its secret first; use that one.
    ensure
      File.unlink(draft)
    end
  end
  ENV["SECRET_KEY_BASE"] = File.read(secret_file).strip
end

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

# The window's title and size come from tokra.conf.json beside this file.
Rack::Handler::Tokra.run(
  Rails.application,
  # invoke_handler receives an Invoke and resolves the frontend promise.
  # Must be Ractor-shareable, so it captures nothing.
  invoke_handler: Ractor.shareable_proc { |invoke|
    invoke.resolve("ack:#{invoke.command}")
    true
  }
)

LOGGER.info { "Goodbye!" }
