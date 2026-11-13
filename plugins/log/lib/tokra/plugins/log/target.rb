# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Target adapted from tauri-plugin-log src/lib.rs

module Tokra
  module Plugins
    module Log
      # One place the plugin writes to, with its own filters and format.
      #
      # Different places want different lines. The page's console wants
      # only what the page logged; a file for bug reports wants
      # everything; the terminal wants it short. A Target pairs a
      # TargetKind with the filters that choose its records and the format
      # that shapes its lines. Its filters run after the builder's, and its
      # format reshapes the line the builder's format already made.
      #
      # Mirrors Tauri's +Target+ (lib.rs:359-393). Filters and formats are
      # Ractor-shareable procs (Ractor.shareable_proc), so a target can be
      # built once and shared.
      #
      # === Examples
      #
      #   Target.new(TargetKind::Stdout.new)
      #
      #   # Only what the page logs, into its own file
      #   Target.new(TargetKind::LogDir.new(file_name: "webview"))
      #     .filter(Ractor.shareable_proc { |metadata| metadata.target.start_with?(WEBVIEW_TARGET) })
      #
      #   # Prefix each line for the terminal
      #   Target.new(TargetKind::Stderr.new)
      #     .format(Ractor.shareable_proc { |message, record| "#{record.level}: #{message}" })
      class Target
        # The TargetKind this target writes to.
        attr_reader :kind

        # The target's filters, in the order they were added.
        attr_reader :filters

        # The target's format, or +nil+ to write the builder's line as is.
        attr_reader :formatter

        # Makes a target that writes to +kind+.
        #
        # [kind] A TargetKind value, such as <tt>TargetKind::Stdout.new</tt>.
        #
        # Raises ArgumentError for anything else.
        def initialize(kind)
          raise ArgumentError, "unknown target kind: #{kind.inspect}" unless KINDS.any? { |known| kind.is_a?(known) }

          @kind = kind
          @filters = []
          @formatter = nil
        end

        # Adds a filter and returns the target. The filter receives each
        # record's Metadata and returns whether the record reaches this
        # target. Every filter has to pass.
        #
        # Raises Ractor::IsolationError for a filter that is not
        # Ractor-shareable.
        #
        # === Example
        #
        #   target.filter(Ractor.shareable_proc { |metadata| metadata.level != :trace })
        def filter(callback = nil, &block)
          filter = callback || block
          shareable!(filter, "filter")
          @filters << filter
          self
        end

        # Sets the target's format and returns the target. The format
        # receives the line the builder's format made and the Record, and
        # returns this target's line; +nil+ keeps the line as it was.
        #
        # Raises Ractor::IsolationError for a format that is not
        # Ractor-shareable.
        #
        # === Example
        #
        #   target.format(Ractor.shareable_proc { |message, _record| "> #{message}" })
        def format(callback = nil, &block)
          formatter = callback || block
          shareable!(formatter, "format")
          @formatter = formatter
          self
        end

        # The kinds a target can write to.
        KINDS = [
          TargetKind::Stdout,
          TargetKind::Stderr,
          TargetKind::Folder,
          TargetKind::LogDir,
          TargetKind::Webview,
          TargetKind::Dispatch,
        ].freeze
        private_constant :KINDS

        private def shareable!(callable, name)
          return if Ractor.shareable?(callable)

          raise Ractor::IsolationError, "#{name} must be Ractor-shareable (use Ractor.shareable_proc)"
        end
      end
    end
  end
end

# SPDX-SnippetEnd
