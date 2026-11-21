# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: attach_logger and Error adapted from tauri-plugin-log
#                      src/lib.rs; logger, max_level, and SetLoggerError from
#                      log 0.4.29 src/lib.rs

require "fileutils"
require "tokra"
require_relative "log/log_level"
require_relative "log/record"
require_relative "log/rotation_strategy"
require_relative "log/timezone_strategy"
require_relative "log/target_kind"
require_relative "log/target"
require_relative "log/rotating_file"
require_relative "log/output"
require_relative "log/logger"
require_relative "log/commands"
require_relative "log/builder"

module Tokra
  module Plugins
    # Logging for Tokra applications, ported from Tauri's log plugin.
    #
    # An app logs from its Ruby code and from its pages, and wants both in
    # one place. Register the plugin that Builder#build makes; its setup
    # attaches a Logger as the process's logger, which Ruby code reaches
    # with Log.logger and the page's <tt>@tauri-apps/plugin-log</tt>
    # reaches through the plugin's <tt>log</tt> command.
    #
    # Tauri's plugin crate re-exports the log crate, whose global logger
    # Rust code logs to with <tt>log::info!</tt>. Tokra keeps the log
    # crate's names here, beside Record and Metadata: Log.logger and
    # Log.max_level are <tt>log::logger</tt> and <tt>log::max_level</tt>.
    #
    # === Example
    #
    #   Tokra::Builder.default
    #     .plugin(Tokra::Plugins::Log::Builder.new.level(:info).build)
    #     .setup(&Ractor.shareable_proc { |_app| Tokra::Plugins::Log.logger.info("started") })
    #     .run(Tokra.generate_context)
    module Log
      # The log plugin's errors (lib.rs:56-68).
      class Error < Tokra::Error
        # Builder#split on a builder that called Builder#skip_logger.
        class LoggerNotInitialized < Error
          # Tauri's message (lib.rs:66-67).
          def initialize(message = "Internal logger disabled and cannot be acquired or attached")
            super
          end
        end
      end

      # A second attach_logger in one process: the process has one logger,
      # and it is set once.
      #
      # Mirrors <tt>log::SetLoggerError</tt> (log lib.rs:462-463, 1551-1555).
      class SetLoggerError < Tokra::Error
        # The log crate's message.
        def initialize(message = "attempted to set a logger after the logging system was already initialized")
          super
        end
      end

      # The logger Log.logger answers before any is attached: one that
      # drops every record, as the log crate's NopLogger does.
      NOP_LOGGER = Ractor.make_shareable(Log::Logger.new(level: :off, filters: [], format: nil, app_name: "", targets: []))
      private_constant :NOP_LOGGER

      # Guards the one attach.
      ATTACH = Mutex.new
      private_constant :ATTACH

      @logger = nil
      @max_level = :off

      # Attaches +log+ as the process's logger, which Log.logger answers
      # and the plugin's <tt>log</tt> command logs to, and records
      # +max_level+ for Log.max_level. Returns +nil+.
      #
      # A process has one logger, set once: a second call raises
      # SetLoggerError and changes nothing, as the log crate's
      # +set_boxed_logger+ does, dropping +log+, as Rust drops the logger
      # it refuses (Logger#drop). So a second app in one process whose log
      # plugin attaches fails to initialize it; build that one with
      # Builder#skip_logger.
      #
      # The logger lives on the main Ractor, where the app's plugins run.
      #
      # Mirrors Tauri's <tt>attach_logger</tt> (lib.rs:711-719).
      #
      # === Example
      #
      #   plugin, max_level, logger = Tokra::Plugins::Log::Builder.new.split(app.handle)
      #   Tokra::Plugins::Log.attach_logger(max_level, logger)
      #   app.handle.plugin(plugin)
      def self.attach_logger(max_level, log)
        ATTACH.synchronize do
          if @logger
            # Rust drops the logger set_boxed_logger refused.
            log.drop
            raise SetLoggerError
          end

          @logger = log
          @max_level = max_level
        end
        nil
      end

      # The process's logger, or one that drops every record when none is
      # attached.
      #
      # Mirrors <tt>log::logger</tt> (log lib.rs:1578-1593).
      #
      # === Example
      #
      #   Tokra::Plugins::Log.logger.warn("db") { "slow query" }
      def self.logger
        @logger || NOP_LOGGER
      end

      # The level filter attach_logger recorded, +:off+ before any attach.
      #
      # Mirrors <tt>log::max_level</tt> (log lib.rs:1393-1401).
      #
      # === Example
      #
      #   Tokra::Plugins::Log.max_level # => :trace
      def self.max_level
        @max_level
      end
    end
  end
end

# SPDX-SnippetEnd

# Tauri's own global API script for the plugin, which defines
# window.__TAURI__.log in a page with withGlobalTauri (build.rs; api-iife.js
# at plugins-workspace d4613ff0, unchanged).
Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("log/api-iife.js", __dir__))
