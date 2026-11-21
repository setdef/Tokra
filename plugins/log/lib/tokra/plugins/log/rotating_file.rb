# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: RotatingFile ported from tauri-plugin-log src/lib.rs

require "fileutils"

module Tokra
  module Plugins
    module Log
      # A log file that rotates when it exceeds its maximum size.
      #
      # The file is <tt><file_name>.log</tt> in +dir+, where +file_name+
      # takes <tt>.log</tt> in place of any extension it has, as Rust's
      # <tt>Path::with_extension</tt> does. #write buffers and #flush
      # writes the buffer, first rotating the file if the buffer would take
      # it past +max_size+. A Folder or LogDir target writes each line and
      # flushes it.
      #
      # Ported from Tauri's private +RotatingFile+ (lib.rs:149-315).
      class RotatingFile # :nodoc:
        # Opens <tt><file_name>.log</tt> in +dir+ for appending, rotating
        # it at once if it is already full, and trims old logs for
        # KeepSome (lib.rs:163-194).
        def initialize(dir, file_name, max_size, rotation_strategy, timezone_strategy)
          @dir = Pathname(dir)
          @file_name = file_name
          @path = @dir.join(file_name).sub_ext(".log")
          @max_size = max_size
          @current_size = 0
          @rotation_strategy = rotation_strategy
          @timezone_strategy = timezone_strategy
          @inner = nil
          @buffer = String.new

          open_file
          rotate if @current_size >= @max_size
          remove_old_files(rotation_strategy.count) if rotation_strategy.is_a?(RotationStrategy::KeepSome)
        end

        # Adds +string+ to the buffer (lib.rs:289-292).
        def write(string)
          @buffer << string.b
        end

        # Writes the buffer, rotating first when the file is not empty and
        # the buffer would take it past the maximum (lib.rs:294-314).
        def flush
          return if @buffer.empty?

          open_file if @inner.nil?
          rotate if @current_size != 0 && @current_size + @buffer.bytesize > @max_size
          inner = @inner or return
          inner.write(@buffer)
          @current_size += @buffer.bytesize
          inner.flush
          @buffer.clear
        end

        # Closes the file, as Rust's drop of a RotatingFile closes the
        # File it holds, and returns +nil+. Ruby closes a File only when
        # it is collected, and Windows refuses to delete or rename a file
        # that is open, so whoever lets a RotatingFile go drops it.
        def drop
          file = @inner
          @inner = nil
          file&.close
          nil
        end

        private def open_file
          file = File.open(@path, "ab")
          @current_size = file.size
          @inner = file
        end

        # lib.rs:206-228.
        private def rotate
          if (file = @inner)
            @inner = nil
            begin
              file.close
            rescue IOError
              nil
            end
          end
          if @path.exist?
            case @rotation_strategy
            when RotationStrategy::KeepAll
              rename_file_to_dated
            when RotationStrategy::KeepSome
              # remove_old_files excludes the active file, so keep one
              # fewer archive to make room for the one about to be made.
              remove_old_files(@rotation_strategy.count - 1)
              rename_file_to_dated
            when RotationStrategy::KeepOne
              File.delete(@path)
            end
          end
          open_file
        end

        # Removes the oldest archives until +keep_count+ remain, not
        # counting the active file (lib.rs:230-262).
        private def remove_old_files(keep_count)
          active = "#{@file_name}.log"
          files = Dir.children(@dir).filter_map do |name|
            next unless name.start_with?(@file_name) && name != active

            date = name.delete_prefix(@file_name)
            next unless date.start_with?("_") && date.end_with?(".log")

            [@dir.join(name), date.delete_prefix("_").delete_suffix(".log")]
          end
          files.sort_by!(&:last)

          return unless files.size > keep_count

          files.first(files.size - keep_count).each { |path, _date| File.delete(path) }
        end

        # Renames the file to <tt><file_name>_<date>.log</tt>, moving an
        # archive already there to <tt>.bak</tt> (lib.rs:264-285).
        private def rename_file_to_dated
          to = @dir.join("#{@file_name}_#{@timezone_strategy.get_now.format(LOG_DATE_FORMAT)}.log")
          # The designated rotated log file name already exists: highly
          # unlikely, but moved aside to .bak.
          File.rename(to, "#{to}.bak") if to.file?
          File.rename(@path, to)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
