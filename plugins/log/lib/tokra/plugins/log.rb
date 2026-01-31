# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tokra"
require "logger"

module Tokra
  # Namespace for Tokra plugins.
  #
  # First-party plugins provide functionality like logging, clipboard access,
  # notifications, and other desktop integrations.
  module Plugins
    # Logging plugin for Tokra desktop applications.
    #
    # Wraps Ruby's Logger with desktop-friendly defaults and
    # integrates with Tokra's plugin lifecycle.
    #
    # == Example
    #
    #   Tokra::Builder.new
    #     .plugin(Tokra::Plugins::Log.new(level: :info, path: "app.log"))
    #     .run
    #
    class Log < Tokra::Plugin
      # Returns the unique plugin identifier.
      def name
        "log"
      end

      # Initializes the logging plugin.
      #
      # +app+::    the application handle
      # +config+:: plugin configuration hash
      #
      # Config options:
      # - +:level+:: log level (+:debug+, +:info+, +:warn+, +:error+, +:fatal+)
      # - +:path+:: log destination (String path or IO, defaults to +$stdout+)
      def initialize(app, config = {})
        raise NotImplementedError
      end

      # Logs a message at the specified level.
      #
      # +level+::   the log level symbol
      # +message+:: the message string to log
      def log(level, message)
        raise NotImplementedError
      end

      # Called on each run loop event.
      def on_event(event)
        raise NotImplementedError
      end
    end
  end
end
