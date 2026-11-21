# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Logger adapted from tauri-plugin-log src/lib.rs
#                      (acquire_logger) and fern 0.7.1 src/log_impl.rs

module Tokra
  module Plugins
    module Log
      # Logger's severity for a trace record, one below Logger's DEBUG,
      # for Logger#add.
      TRACE = -1

      # The logger the log plugin installs: one logger for the app's Ruby
      # code and its pages.
      #
      # A desktop app logs from two places, its Ruby code and its pages,
      # and you want both in the same terminal and the same files, in one
      # format, with the page's lines marked as the page's. The plugin's
      # setup makes this logger from its Builder and attaches it as the
      # process's logger, where Log.logger finds it and the page's
      # <tt>log</tt> command logs to it. It takes each record through the
      # builder's level, filters, and format, then through each target's
      # filters and format, to its targets, as Tauri's fern dispatch does.
      #
      # Ruby code logs with #trace, #debug, #info, #warn, #error, and
      # #fatal, which take Ruby's ::Logger arguments, so the logger also
      # stands in for a ::Logger a library takes. A record's target is the
      # +progname+ passed, or the app's name.
      #
      # Mirrors the <tt>Box<dyn log::Log></tt> Tauri's <tt>acquire_logger</tt>
      # makes (lib.rs:567-664).
      #
      # === Example
      #
      #   log = Tokra::Plugins::Log.logger
      #   log.info("started")
      #   log.warn("db") { "slow query" }   # target "db"
      #   ActiveRecord::Base.logger = log
      class Logger
        # ::Logger's severities by the level each logs at; FATAL and
        # UNKNOWN log at +:error+, log's highest level.
        SEVERITY_LEVELS = { TRACE => :trace, 0 => :debug, 1 => :info, 2 => :warn }.freeze
        private_constant :SEVERITY_LEVELS

        # log's level filters, from Off up.
        LEVEL_FILTERS = %i[off error warn info debug trace].freeze
        private_constant :LEVEL_FILTERS

        # Makes a logger. Builder#build's setup and Builder#split make one
        # from the builder; call those rather than this.
        #
        # [level] The lowest level logged, a level filter such as +:info+.
        # [filters] Blocks that receive each record's Metadata and return
        #           whether to log it.
        # [format] The builder's format, or +nil+.
        # [app_name] The target of a Ruby record that names none.
        # [targets] Each target's filters, format, and output, as
        #           <tt>[filters, format, output]</tt>.
        def initialize(level:, filters:, format:, app_name:, targets:)
          @max_level = LEVEL_FILTERS.index(level) || LEVEL_FILTERS.size
          @filters = filters.dup.freeze
          @format = format
          @app_name = app_name
          @targets = targets.dup.freeze
        end

        # Logs a trace message: very low priority, often extremely verbose,
        # information. Takes ::Logger's arguments, as #add does.
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

        # Logs +message+ at +severity+, as ::Logger#add takes them, and
        # returns +true+.
        #
        # +severity+ is a ::Logger severity or TRACE; FATAL, UNKNOWN, and
        # +nil+ log at +:error+. +progname+ becomes the record's target,
        # the app's name when +nil+. Without a +message+, the block's value
        # is the message, or else +progname+ is, with the default target. A
        # record below the builder's level skips the block. A message that
        # is not a String is written as ::Logger writes it.
        #
        # === Example
        #
        #   log.add(::Logger::WARN, "slow", "db")
        #   log.add(::Logger::INFO) { "computed #{expensive}" }
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
          log(Record.new(args: message_text(message), level:, target: progname || @app_name))
          true
        end

        # Logs +record+, a Record, as Tauri's dispatch does: the builder's
        # level and filters, the builder's format, then each target's
        # filters, format, and output; returns +nil+. This is the
        # <tt>log::Log</tt> method Tauri's <tt>log</tt> command calls on the
        # global logger (fern log_impl.rs:446-550; commands.rs:40).
        #
        # === Example
        #
        #   logger.log(Tokra::Plugins::Log::Record.new(args: "ready", level: :info, target: "boot"))
        def log(record)
          metadata = record.metadata
          return unless LEVEL_FILTERS.index(metadata.level).to_i <= @max_level
          return unless @filters.all? { |filter| filter.call(metadata) }

          record = finish(record, @format)
          @targets.each do |filters, formatter, output|
            next unless filters.all? { |filter| filter.call(metadata) }

            output.log(finish(record, formatter))
          end
          nil
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
      end
    end
  end
end

# SPDX-SnippetEnd
