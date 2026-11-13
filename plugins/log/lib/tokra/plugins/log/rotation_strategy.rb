# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: RotationStrategy adapted from tauri-plugin-log src/lib.rs

module Tokra
  module Plugins
    module Log
      # What happens to a log file that reaches Builder#max_file_size.
      #
      # A log file grows for as long as the app runs, and an app that runs
      # for weeks fills a disk. When the next line would take a file past
      # the maximum, the plugin rotates it: it deletes the old file or
      # renames it to <tt><file_name>_<date>.log</tt>, in the builder's
      # TimezoneStrategy, and starts a new one. The strategy is set on the
      # Builder and applies to every Folder and LogDir target; KeepOne is
      # the default.
      #
      # Mirrors Tauri's +RotationStrategy+ (lib.rs:122-130).
      #
      # === Examples
      #
      #   Builder.new.rotation_strategy(RotationStrategy::KeepAll.new)
      #   Builder.new.rotation_strategy(RotationStrategy::KeepSome.new(5))
      module RotationStrategy
        # Keeps all the logs, renaming them to include the date.
        class KeepAll < Data.define; end

        # Keeps only the most recent log, up to its maximum size.
        class KeepOne < Data.define; end

        # Keeps +count+ of the most recent logs, renaming them to include
        # the date.
        class KeepSome < Data.define(:count)
          # :attr_reader: count
          # How many dated logs to keep beside the current one.
        end
      end
    end
  end
end

# SPDX-SnippetEnd
