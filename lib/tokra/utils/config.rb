# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "ferro/url"

module Tokra
  module Utils
    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: the config schema of tauri-utils src/config.rs at
    #   vendor/tauri 9f0306fbc, read as serde 1.0.228 reads it
    #++

    # Your app's config: every type <tt>tokra.conf.json</tt> holds.
    #
    # A Tauri app describes itself in one file: its identifier and name,
    # the windows it opens, its security settings, how it is built and
    # bundled, and each plugin's settings. Tokra reads the same file under
    # its own name, with the same keys, aliases, defaults, and errors, so
    # Tauri's configuration reference describes a Tokra config too (ADR
    # 014 §4).
    #
    # This module holds the types, one per Tauri struct or enum, each a
    # frozen value. Tokra.generate_context reads the file and hands you
    # the whole of it as Config.
    #
    # Mirrors Tauri's <tt>tauri_utils::config</tt> module (tauri-utils
    # src/config.rs).
    #
    # === Examples
    #
    #   config = Tokra.generate_context.config
    #   config.identifier                #=> "com.example.app"
    #   config.app.windows.first.title   #=> "Tokra App"
    #   config.plugins["log"]            #=> {"level" => "info"}
    module Config
      # One field of a config struct, as its serde attributes describe it:
      # the Ruby member, the JSON key, the reader of its value, its
      # <tt>alias</tt>es, its <tt>default</tt>, and whether it is a Rust
      # +Option+, which reads +null+ as +nil+.
      class Field < Data.define(:member, :key, :reader, :aliases, :default, :option) # :nodoc:
        # The default of a field without one.
        NONE = Object.new.freeze

        # A field with neither a default nor an +Option+: a map without it
        # is serde's <tt>missing field</tt>.
        def self.required(member, key, reader, aliases: [])
          new(member:, key:, reader:, aliases:, default: NONE, option: false)
        end

        # A field with <tt>#[serde(default)]</tt> or <tt>default =
        # "..."</tt>: +default+ is its value, already read, which every
        # struct that takes it shares, so it is made shareable. +option+
        # marks a defaulted Rust +Option+.
        def self.defaulted(member, key, reader, default, aliases: [], option: false)
          new(member:, key:, reader:, aliases:, default: Ractor.make_shareable(default), option:)
        end

        # A Rust +Option+ without a default: +null+ or a missing key reads
        # +nil+ from a map, and a sequence has to reach it.
        def self.option(member, key, reader, aliases: [])
          new(member:, key:, reader:, aliases:, default: NONE, option: true)
        end

        # Whether the field has a default.
        def default?
          !NONE.equal?(default)
        end
      end

      # The values of +fields+ that +value+ holds, by member, read as
      # serde's derive reads the struct +name+ (Ipc::Serde.struct_fields).
      def self.read_struct(value, name, fields, deny_unknown: true) # :nodoc:
        by_key = fields.to_h { |field| [field.key, field] }
        read = Ipc::Serde.struct_fields(value, name, fields.map(&:key),
          optional: fields.select(&:option).map(&:key),
          aliases: fields.reject { |field| field.aliases.empty? }.to_h { |field| [field.key, field.aliases] },
          defaults: fields.select(&:default?).to_h { |field| [field.key, field.default] },
          deny_unknown:) { |key, raw| by_key.fetch(key).reader.call(raw) }
        fields.to_h { |field| [field.member, read[field.key]] }
      end

      # The keywords a struct's +new+ fills in when you leave them out:
      # each field's default, and +nil+ for an +Option+. A field Tauri
      # requires has none, so +new+ raises without it.
      def self.defaults_of(fields) # :nodoc:
        fields.select { |field| field.default? || field.option }.to_h do |field|
          [field.member, field.default? ? field.default : nil]
        end
      end

      # +value+ as a Rust +PathBuf+, a Pathname: serde's path visitor takes
      # a string, and words anything else <tt>expected path string</tt>
      # (serde_core de/impls.rs:1824-1874).
      def self.path(value) # :nodoc:
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "path string") unless value.is_a?(String)

        Pathname.new(value)
      end

      # +value+ as a Rust +Vec+, each element read by the block.
      def self.sequence(value, &) # :nodoc:
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a sequence") unless value.is_a?(Array)

        value.map(&)
      end

      # +value+ as a Rust <tt>HashMap<String, T></tt>, each value read by
      # the block.
      def self.map(value, &) # :nodoc:
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a map") unless value.is_a?(Hash)

        value.transform_values(&)
      end

      # +value+ as a Rust <tt>HashMap<PathBuf, PathBuf></tt>: each key and
      # value a Pathname. A JSON object's keys are strings, which a path
      # always takes.
      def self.path_map(value) # :nodoc:
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a map") unless value.is_a?(Hash)

        value.to_h { |key, item| [Pathname.new(key), path(item)] }
      end

      # The values of +fields+ that +rest+ holds, by member, for the struct
      # variant +name+ (<tt>"Enum::Variant"</tt>) of an internally tagged
      # enum, where +rest+ is what Ipc::Serde.internally_tagged left of the
      # value.
      #
      # serde buffers the value as its Content and reads the variant from
      # it (serde_derive de/enum_internally.rs:20-62): a map as a struct is
      # read, and a sequence element by element as serde_derive's
      # +visit_seq+ reads one, failing where it runs out on a field without
      # a default, and then as serde's SeqDeserializer ends, refusing
      # elements left over (serde private/de.rs, ContentDeserializer;
      # serde_core de/value.rs, SeqDeserializer::end and ExpectedInSeq).
      def self.read_variant(rest, name, fields) # :nodoc:
        return read_struct(rest, name, fields) if rest.is_a?(Hash)

        seq = rest #: Array[json_value]
        expecting = "struct variant #{name} with #{elements(fields.size)}"
        values = fields.each_with_index.to_h do |field, index|
          if index >= seq.size
            raise Ipc::CommandItem::Mismatch, "invalid length #{index}, expected #{expecting}" unless field.default?

            next [field.member, field.default]
          end
          raw = seq.fetch(index)
          [field.member, (raw.nil? && field.option) ? nil : field.reader.call(raw)]
        end
        if seq.size > fields.size
          raise Ipc::CommandItem::Mismatch, "invalid length #{seq.size}, expected #{elements(fields.size)} in sequence"
        end

        values
      end

      # Checks +rest+ for a unit variant of an internally tagged enum, as
      # serde's InternallyTaggedUnitVisitor reads it (serde
      # private/de.rs:2956-2996): a map's other keys are stepped over, even
      # where the enum denies unknown fields, and a sequence must hold
      # nothing past the tag.
      def self.read_unit_variant(rest) # :nodoc:
        return unless rest.is_a?(Array) && !rest.empty?

        raise Ipc::CommandItem::Mismatch, "invalid length #{rest.size}, expected 0 elements in sequence"
      end

      # +count+ elements, as serde words a length.
      def self.elements(count)
        (count == 1) ? "1 element" : "#{count} elements"
      end
      private_class_method :elements

      # +value+ as a Rust <tt>url::Url</tt>: a Ferro::Url::Url, which
      # ferro-url parses with the url crate itself, frozen. A string url
      # refuses fails with url 2.5.4's words, <tt>"{error}: {input:?}"</tt>
      # (url src/lib.rs:2886-2912). ferro-url 0.1.0 binds url 2.5.8,
      # whose parser differs from 2.5.4's only in refactors (plan 054,
      # decision 25). The one difference left unverified is Unicode data:
      # ferro-url's idna_adapter 1.2.2 reads ICU4X 2.4's, where Tauri's
      # idna_adapter 1.2.0 reads ICU4X 1.5's, so only a hostname with a
      # code point assigned since then could read differently.
      def self.url(value) # :nodoc:
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a string representing an URL") unless value.is_a?(String)

        Ferro::Url::Url.parse(value).freeze
      rescue Ferro::Url::ParseError => e
        raise Ipc::CommandItem::Mismatch, "#{e.message}: #{Ipc::Unexpected.debug(value.to_s)}"
      end

      #--
      # SPDX-SnippetEnd
      #++
    end
  end
end

require_relative "config/logical_position"
require_relative "config/prevent_overflow_config"
require_relative "config/scroll_bar_style"
require_relative "config/window_config"
require_relative "config/csp"
require_relative "config/fs_scope"
require_relative "config/header_config"
require_relative "config/capability_entry"
require_relative "config/pattern_kind"
require_relative "config/security_config"
require_relative "config/tray_icon_config"
require_relative "config/app_config"
require_relative "config/frontend_dist"
require_relative "config/hook_command"
require_relative "config/runner_config"
require_relative "config/build_config"
require_relative "config/uuid"
require_relative "config/bundle_target"
require_relative "config/updater"
require_relative "config/bundle_resources"
require_relative "config/file_association"
require_relative "config/windows_config"
require_relative "config/linux_config"
require_relative "config/mac_config"
require_relative "config/ios_config"
require_relative "config/android_config"
require_relative "config/bundle_config"
require_relative "config/config"
require_relative "config/parse"
