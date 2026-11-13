# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Outputs adapted from tauri-plugin-log src/lib.rs
#                      (acquire_logger) and fern 0.7.1 src/log_impl.rs

module Tokra
  module Plugins
    module Log
      # The writers behind each TargetKind, as fern's outputs that Tauri's
      # acquire_logger chains (lib.rs:587-657). Each takes a Record whose
      # +args+ is the finished line.
      module Output # :nodoc:
        # Where a write that fails is reported, in fern's words
        # (fern log_impl.rs:874-893).
        module Fallback # :nodoc:
          # Runs the block, reporting an IO failure for +record+ to
          # +$stderr+ instead of raising it.
          def self.on_error(record)
            yield
          rescue IOError, SystemCallError => e
            $stderr.write("Error performing logging.\n\tattempted to log: #{record.args}\n\t" \
              "record: #{record.inspect}\n\tlogging error: #{e.message}")
          end
        end

        # Standard output or error: the line and a newline, flushed
        # (fern log_impl.rs:553-625). The stream is looked up for each
        # line, so a reassigned +$stdout+ is the one written to.
        class Stream # :nodoc:
          # [stream] +:stdout+ or +:stderr+.
          def initialize(stream)
            @stream = stream
            @lock = Mutex.new
          end

          # Writes +record+'s line.
          def log(record)
            Fallback.on_error(record) do
              @lock.synchronize do
                io = (@stream == :stderr) ? $stderr : $stdout
                io.write("#{record.args}\n")
                io.flush
              end
            end
          end
        end

        # A RotatingFile, written as fern writes a boxed writer: the line
        # and a newline, then a flush (fern log_impl.rs:596-621).
        class Writer # :nodoc:
          # [file] A RotatingFile.
          def initialize(file)
            @file = file
            @lock = Mutex.new
          end

          # Writes +record+'s line.
          def log(record)
            Fallback.on_error(record) do
              @lock.synchronize do
                @file.write("#{record.args}\n")
                @file.flush
              end
            end
          end
        end

        # The webview: a <tt>log://log</tt> event carrying the
        # RecordPayload (lib.rs:317-321, 642-655).
        class Webview # :nodoc:
          # [app_handle] The AppHandle that emits.
          def initialize(app_handle)
            @app_handle = app_handle
          end

          # Emits +record+'s line and LogLevel.
          def log(record)
            @app_handle.emit("log://log", { message: record.args, level: LogLevel.from(record.level) })
          end
        end

        # An app's own Logger (lib.rs:656).
        class Dispatch # :nodoc:
          # Logger's severities for each level; Logger has no trace.
          SEVERITIES = { error: 3, warn: 2, info: 1, debug: 0, trace: 0 }.freeze

          # [logger] Any object with Logger's +add+.
          def initialize(logger)
            @logger = logger
          end

          # Adds +record+'s line at its severity, with its target as the
          # progname.
          def log(record)
            @logger.add(SEVERITIES.fetch(record.level), record.args, record.target)
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
