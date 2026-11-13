# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Plugin adapted from tauri-plugin-log src/lib.rs
#                      (acquire_logger) and fern 0.7.1 src/log_impl.rs

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
require_relative "log/builder"

module Tokra
  module Plugins
    # Logging for Tokra applications, ported from Tauri's log plugin.
    #
    # Use Builder to make the Plugin.
    module Log
      # Logger's severity for a trace record, one below Logger's DEBUG,
      # for Plugin#add.
      TRACE = -1

      # The log plugin: one logger for the app's Ruby code and its pages.
      #
      # A desktop app logs from two places, its Ruby code and its pages,
      # and you want both in the same terminal and the same files, in one
      # format, with the page's lines marked as the page's. Built by
      # Builder, the plugin takes each record through the builder's level,
      # filters, and format, then through each target's filters and
      # format, to its targets, as Tauri's fern dispatch does.
      #
      # Ruby code logs with #trace, #debug, #info, #warn, #error, and
      # #fatal, which take Logger's arguments, so the plugin also stands in
      # for a Logger a library takes. A record's target is the +progname+
      # passed, or the app's name.
      #
      # Mirrors the logger Tauri's plugin installs (lib.rs:567-708).
      #
      # === Example
      #
      #   log = Tokra::Plugins::Log::Builder.new.app_handle(app.handle).build
      #   app.handle.plugin(log)
      #
      #   log.info("started")
      #   log.warn("db") { "slow query" }   # target "db"
      #   ActiveRecord::Base.logger = log
      class Plugin < Tokra::Plugin
        # Logger's severities by the level each logs at; FATAL and UNKNOWN
        # log at +:error+, log's highest level.
        SEVERITY_LEVELS = { TRACE => :trace, 0 => :debug, 1 => :info, 2 => :warn }.freeze
        private_constant :SEVERITY_LEVELS

        # log's level filters, from Off up.
        LEVEL_FILTERS = %i[off error warn info debug trace].freeze
        private_constant :LEVEL_FILTERS

        # Returns <tt>"log"</tt>, Tauri's plugin name (lib.rs:667).
        def name
          "log"
        end

        # Makes the plugin from +builder+, opening each target's output
        # (lib.rs:567-664). Call Builder#build rather than this.
        #
        # [builder] A configured Builder.
        def initialize(builder)
          super(builder.configured_app_handle)
          @max_level = LEVEL_FILTERS.index(builder.configured_level) || LEVEL_FILTERS.size
          @filters = builder.configured_filters.dup.freeze
          @format = builder.configured_format
          @app_name = builder.configured_app_name || builder.configured_app_handle&.package_info&.name || "app"
          @targets = builder.configured_targets.map do |target|
            [target.filters.dup.freeze, target.formatter, output(target.kind, builder)]
          end
        end

        # Initializes the plugin with +app+ and +config+, its slice of the
        # app config's +plugins+, which must be null: Tauri's log plugin
        # takes no config, and its setup fails the app with "Error
        # deserializing 'plugins.log' within your Tauri configuration:
        # ..." (lib.rs:691-708; plugin.rs:793-806). Tokra's message names
        # the Tokra configuration (doc/contributors/design/config.md, "File
        # names").
        def initialize_plugin(app, config)
          Tokra::Plugin::Builder::Unit.deserialize(config)
          super
        rescue Tokra::Ipc::CommandItem::Mismatch => e
          raise Tokra::Error, "Error deserializing 'plugins.log' within your Tokra configuration: #{e.message}"
        end

        # Logs a trace message: very low priority, often extremely verbose,
        # information. Takes Logger's arguments, as #add does.
        #
        # === Example
        #
        #   log.trace("frame drawn")
        def trace(progname = nil, &)
          add(TRACE, nil, progname, &)
        end

        # Logs a debug message: lower priority information.
        #
        # === Example
        #
        #   log.debug("cache") { "miss for #{key}" }
        def debug(progname = nil, &)
          add(0, nil, progname, &)
        end

        # Logs an info message: useful information.
        #
        # === Example
        #
        #   log.info("window opened")
        def info(progname = nil, &)
          add(1, nil, progname, &)
        end

        # Logs a warn message: hazardous situations.
        #
        # === Example
        #
        #   log.warn("disk nearly full")
        def warn(progname = nil, &)
          add(2, nil, progname, &)
        end

        # Logs an error message: very serious errors.
        #
        # === Example
        #
        #   log.error(exception)
        def error(progname = nil, &)
          add(3, nil, progname, &)
        end

        # Logs a message at +:error+, log's highest level, for Logger's
        # FATAL.
        #
        # === Example
        #
        #   log.fatal("cannot start")
        def fatal(progname = nil, &)
          add(4, nil, progname, &)
        end

        # Logs +message+ at +severity+, as Logger#add takes them, and
        # returns +true+.
        #
        # +severity+ is a Logger severity or TRACE; FATAL, UNKNOWN, and
        # +nil+ log at +:error+. +progname+ becomes the record's target,
        # the app's name when +nil+. Without a +message+, the block's value
        # is the message, or else +progname+ is, with the default target. A
        # record below the builder's level skips the block. A message that
        # is not a String is written as Logger writes it.
        #
        # === Example
        #
        #   log.add(Logger::WARN, "slow", "db")
        #   log.add(Logger::INFO) { "computed #{expensive}" }
        def add(severity, message = nil, progname = nil)
          level = level_of(severity)
          return true unless LEVEL_FILTERS.index(level).to_i <= @max_level

          if message.nil?
            if block_given?
              message = yield
            else
              message = progname
              progname = nil
            end
          end
          dispatch(Record.new(args: message_text(message), level:, target: progname || @app_name))
          true
        end

        # Logs +record+ as Tauri's dispatch does: the builder's level and
        # filters, the builder's format, then each target's filters,
        # format, and output (fern log_impl.rs:446-550).
        private def dispatch(record)
          metadata = record.metadata
          return unless LEVEL_FILTERS.index(metadata.level).to_i <= @max_level
          return unless @filters.all? { |filter| filter.call(metadata) }

          record = finish(record, @format)
          @targets.each do |filters, formatter, output|
            next unless filters.all? { |filter| filter.call(metadata) }

            output.log(finish(record, formatter))
          end
        end

        # +record+ with its args replaced by +format+'s line, or as it was
        # when there is no format or it returns +nil+, as fern finishes a
        # record whose format never calls finish (log_impl.rs:452-472).
        private def finish(record, format)
          return record unless format

          line = format.call(record.args, record)
          line.nil? ? record : record.with(args: line.to_s)
        end

        private def level_of(severity)
          return :error if severity.nil?
          return :trace if severity < TRACE

          SEVERITY_LEVELS.fetch(severity, :error)
        end

        # Logger::Formatter#msg2str.
        private def message_text(message)
          case message
          when ::String then message
          when ::Exception then "#{message.message} (#{message.class})\n#{message.backtrace&.join("\n")}"
          else message.inspect
          end
        end

        # The output for +kind+ (lib.rs:587-657).
        private def output(kind, builder)
          case kind
          when TargetKind::Stdout then Output::Stream.new(:stdout)
          when TargetKind::Stderr then Output::Stream.new(:stderr)
          when TargetKind::Folder then file_output(kind.path, kind.file_name, builder)
          when TargetKind::LogDir then file_output(log_dir(builder), kind.file_name, builder)
          when TargetKind::Webview then Output::Webview.new(handle_for("Webview", builder))
          when TargetKind::Dispatch then Output::Dispatch.new(kind.logger)
          else raise ArgumentError, "unknown target kind: #{kind.inspect}"
          end
        end

        # A RotatingFile in +dir+, which is created first (lib.rs:613-641).
        private def file_output(dir, file_name, builder)
          FileUtils.mkdir_p(dir)
          file = RotatingFile.new(dir, file_name || @app_name, builder.configured_max_file_size,
            builder.configured_rotation_strategy, builder.configured_timezone_strategy)
          Output::Writer.new(file)
        end

        private def log_dir(builder)
          resolver = builder.configured_path_resolver || handle_for("LogDir", builder).path
          resolver.app_log_dir
        end

        private def handle_for(kind, builder)
          builder.configured_app_handle ||
            raise(ArgumentError, "a #{kind} target needs the app handle: call Builder#app_handle")
        end
      end
    end
  end
end

# SPDX-SnippetEnd

# Tauri's own global API script for the plugin, which defines
# window.__TAURI__.log in a page with withGlobalTauri (build.rs; api-iife.js
# at plugins-workspace d4613ff0, unchanged).
Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("log/api-iife.js", __dir__))
