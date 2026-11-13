# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Plugins
    module Log
      # The level and target of a record, which filters decide by.
      #
      # A filter decides whether a record goes on before anything formats
      # it, so it sees only what the record is about: how severe it is and
      # who logged it. +level+ is one of +:error+, +:warn+, +:info+,
      # +:debug+, and +:trace+; +target+ is the record's target, such as
      # the app's name for Ruby code or <tt>"webview:..."</tt> for a page.
      #
      # Mirrors <tt>log::Metadata</tt>, which Tauri's filters receive
      # (lib.rs:376-383, 493-499).
      #
      # === Example
      #
      #   Builder.new.filter(Ractor.shareable_proc { |metadata| metadata.level != :trace })
      class Metadata < Data.define(:level, :target)
        # :attr_reader: level
        # The record's level name, such as +:info+.

        # :attr_reader: target
        # Who logged the record, such as <tt>"webview:main.js"</tt>.
      end

      # One message on its way through the plugin.
      #
      # Each log call makes a record, and each format along the way
      # replaces its +args+ with the line it made, so a target's format
      # sees the line the builder's format wrote. +args+ is the message,
      # +level+ a level name, +target+ who logged it, and +file+, +line+,
      # and +key_values+ what a page sent with it.
      #
      # Mirrors <tt>log::Record</tt> as fern passes it on
      # (fern 0.7.1 log_impl.rs:531-550).
      #
      # === Example
      #
      #   Builder.new.format(Ractor.shareable_proc { |message, record| "#{record.target}: #{message}" })
      class Record < Data.define(:args, :level, :target, :file, :line, :key_values)
        # :attr_reader: args
        # The message, or the line a format made of it.

        # :attr_reader: level
        # The level name, such as +:warn+.

        # :attr_reader: target
        # Who logged the record.

        # :attr_reader: file
        # The source file the page named, or +nil+.

        # :attr_reader: line
        # The line in +file+ the page named, or +nil+.

        # :attr_reader: key_values
        # The Hash of String pairs the page sent with the message.

        # Makes a record. Only +args+, +level+, and +target+ are needed.
        #
        # [args] The message String.
        # [level] A level name, such as +:info+.
        # [target] Who logged it, a String.
        # [file] The source file, or +nil+.
        # [line] The line number in +file+, or +nil+.
        # [key_values] A Hash of String pairs.
        def initialize(args:, level:, target:, file: nil, line: nil, key_values: {})
          super
        end

        # The record's Metadata.
        #
        # === Example
        #
        #   Record.new(args: "hi", level: :info, target: "app").metadata.level  #=> :info
        def metadata
          Metadata.new(level:, target:)
        end
      end
    end
  end
end
