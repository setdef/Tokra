# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: Argument errors from tauri ipc/command.rs and error.rs;
#                      the messages are serde's (serde_core 1.0.228
#                      de/mod.rs) as serde_json 1.0.150 src/value/de.rs and
#                      src/error.rs produce them

module Tokra
  module Plugins
    module Dialog
      module Commands
        # Reads one command's arguments the way Tauri deserializes them.
        #
        # Tauri's commands take typed arguments, and serde turns the
        # frontend's JSON into them or rejects the invoke with a precise
        # message: a missing key, a wrong type, an unknown enum variant. The
        # frontend's error handling, and a developer reading the console,
        # depend on those words.
        #
        # This class checks each argument the plugin's commands take, in the
        # order Tauri reads them, and raises ArgumentError with Tauri's
        # <tt>invalid args `key` for command `name`: ...</tt> message
        # (tauri error.rs:59-60) and serde_json's text for what was wrong.
        #
        # === Examples
        #
        #   args = Arguments.new({ "message" => 1 }, "message")
        #   args.string("message")
        #   # raises ArgumentError: invalid args `message` for command `message`:
        #   #   invalid type: integer `1`, expected a string
        #
        #   Arguments.new({ "options" => {} }, "open").open_options.multiple  #=> false
        class Arguments
          # The variants of MessageDialogButtons, in declaration order, as
          # serde lists them (models.rs:51-67).
          BUTTONS = %w[Ok OkCancel YesNo YesNoCancel OkCustom OkCancelCustom YesNoCancelCustom].freeze

          # The tuple variants and their lengths.
          TUPLES = { "OkCancelCustom" => 2, "YesNoCancelCustom" => 3 }.freeze

          # The variants of PickerMode, lowercased by serde (lib.rs:47-54).
          PICKER_MODES = %w[document media image video].freeze

          # The variants of FileAccessMode, lowercased by serde
          # (lib.rs:56-61).
          FILE_ACCESS_MODES = %w[copy scoped].freeze

          # What serde says went wrong with one value.
          class Mismatch < StandardError; end

          # Creates a reader for +payload+, the invoke's arguments, of
          # +command+.
          #
          # [payload] the invoke's payload Hash.
          # [command] the command name, for the messages.
          def initialize(payload, command)
            @payload = payload || {}
            @command = command
          end

          # The value for +key+, or +nil+ when the frontend left it out.
          #
          # === Example
          #
          #   args.optional("kind")  #=> "warning"
          def optional(key)
            @payload[key]
          end

          # The String for required +key+ (a Rust +String+).
          #
          # === Example
          #
          #   args.string("message")  #=> "Saved"
          def string(key)
            argument(key) { string_value(required(key)) }
          end

          # The String for +key+, or +nil+ when absent or null (a Rust
          # <tt>Option<String></tt>).
          #
          # === Example
          #
          #   args.optional_string("title")  #=> nil
          def optional_string(key)
            value = optional(key)
            argument(key) { value.nil? ? nil : string_value(value) }
          end

          # The MessageDialogKind for +value+ at +key+, or +nil+: any
          # string, ignoring case, and Info for anything unknown
          # (models.rs:20-33).
          #
          # === Example
          #
          #   args.kind("kind", "WARNING")  #=> MessageDialogKind::Warning
          def kind(key, value)
            return nil if value.nil?

            argument(key) do
              case string_value(value).downcase
              when "warning" then MessageDialogKind::Warning
              when "error" then MessageDialogKind::Error
              else MessageDialogKind::Info
              end
            end
          end

          # The MessageDialogButtons for +value+ at +key+, or +nil+, read as
          # serde reads an externally tagged enum: a variant's name, or an
          # object with the variant's name as its one key
          # (serde_json value/de.rs:328-347, 1066-1107).
          #
          # === Example
          #
          #   args.buttons("buttons", { "OkCustom" => "Fine" })  #=> MessageDialogButtons::OkCustom.new(ok: "Fine")
          def buttons(key, value)
            return nil if value.nil?

            argument(key) do
              variant, content = enum_value(value, BUTTONS)
              case variant
              when "OkCustom" then MessageDialogButtons::OkCustom.new(ok: newtype(content) { |text| string_value(text) })
              when "OkCancelCustom"
                ok, cancel = tuple(content, variant)
                MessageDialogButtons::OkCancelCustom.new(ok:, cancel:)
              when "YesNoCancelCustom"
                yes, no, cancel = tuple(content, variant)
                MessageDialogButtons::YesNoCancelCustom.new(yes:, no:, cancel:)
              else
                unit(content)
                MessageDialogButtons.const_get(variant, false)
              end
            end
          end

          # The open command's required +options+ (commands.rs:36-71).
          #
          # === Example
          #
          #   args.open_options.directory  #=> false
          def open_options
            argument("options") do
              fields = struct_value(required("options"), "OpenDialogOptions", {
                "title" => [nil, -> (value) { option(value) { string_value(value) } }],
                "filters" => [[], -> (value) { filters(value) }],
                "multiple" => [false, -> (value) { bool(value) }],
                "directory" => [false, -> (value) { bool(value) }],
                "defaultPath" => [nil, -> (value) { option(value) { path(value) } }],
                "recursive" => [false, -> (value) { bool(value) }],
                "canCreateDirectories" => [nil, -> (value) { option(value) { bool(value) } }],
                "pickerMode" => [nil, -> (value) { option(value) { picker_mode(value) } }],
                "fileAccessMode" => [nil, -> (value) { option(value) { file_access_mode(value) } }],
              })
              OpenDialogOptions.new(*fields)
            end
          end

          # The save command's required +options+ (commands.rs:73-87).
          #
          # === Example
          #
          #   args.save_options.default_path  #=> "/tmp/out.txt"
          def save_options
            argument("options") do
              fields = struct_value(required("options"), "SaveDialogOptions", {
                "title" => [nil, -> (value) { option(value) { string_value(value) } }],
                "filters" => [[], -> (value) { filters(value) }],
                "defaultPath" => [nil, -> (value) { option(value) { path(value) } }],
                "canCreateDirectories" => [nil, -> (value) { option(value) { bool(value) } }],
              })
              SaveDialogOptions.new(*fields)
            end
          end

          # Runs the block, turning a Mismatch into Tauri's InvalidArgs
          # message for +key+.
          private def argument(key)
            yield
          rescue Mismatch => e
            raise ArgumentError, "invalid args `#{key}` for command `#{@command}`: #{e.message}"
          end

          # A required argument, or Tauri's missing-key message
          # (tauri ipc/command.rs:97-102).
          private def required(key)
            return @payload[key] if @payload.key?(key)

            raise Mismatch, "command #{@command} missing required key #{key}"
          end

          private def mismatch(value, expected)
            raise Mismatch, "invalid type: #{unexpected(value)}, expected #{expected}"
          end

          # serde_json's description of a JSON value (value/de.rs:1395-1404,
          # error.rs:465-478).
          private def unexpected(value)
            case value
            when nil then "null"
            when true, false then "boolean `#{value}`"
            when Integer then "integer `#{value}`"
            when Float then "floating point `#{value}`"
            when String then "string #{debug(value)}"
            when Array then "sequence"
            else "map"
            end
          end

          # +string+ quoted as Rust's Debug quotes a str: escapes for
          # quotes, backslashes, tabs, returns, newlines, and NUL, and
          # <tt>\u{..}</tt> for other control characters
          # (char::escape_debug). Printable text passes as it is.
          private def debug(string)
            escaped = string.each_char.map do |char|
              case char
              when "\t" then "\\t"
              when "\r" then "\\r"
              when "\n" then "\\n"
              when "\\" then "\\\\"
              when '"' then "\\\""
              when "\0" then "\\0"
              else (char.ord < 0x20 || char.ord == 0x7F) ? format("\\u{%x}", char.ord) : char
              end
            end
            "\"#{escaped.join}\""
          end

          private def string_value(value)
            value.is_a?(String) ? value : mismatch(value, "a string")
          end

          private def bool(value)
            [true, false].include?(value) ? value : mismatch(value, "a boolean")
          end

          # A PathBuf, which serde reads from a string (serde_core
          # de/impls.rs:1831).
          private def path(value)
            value.is_a?(String) ? value : mismatch(value, "path string")
          end

          private def option(value)
            value.nil? ? nil : yield
          end

          private def filters(value)
            mismatch(value, "a sequence") unless value.is_a?(Array)
            value.map do |filter|
              name, extensions = struct_value(filter, "DialogFilter", {
                "name" => [:required, -> (item) { string_value(item) }],
                "extensions" => [:required, -> (item) { sequence(item) { |extension| string_value(extension) } }],
              })
              DialogFilter.new(name:, extensions:)
            end
          end

          private def sequence(value, &)
            mismatch(value, "a sequence") unless value.is_a?(Array)
            value.map(&)
          end

          # The fields of a derived struct, in declaration order: each key of
          # the object in its order, then each missing field's default, or
          # serde's missing-field message for one without.
          private def struct_value(value, name, fields)
            mismatch(value, "struct #{name}") unless value.is_a?(Hash)
            read = {}
            value.each do |key, item|
              field = fields[key]
              read[key] = field.last.call(item) if field
            end
            fields.map do |key, (default, _reader)|
              next read[key] if read.key?(key)
              raise Mismatch, "missing field `#{key}`" if default == :required

              default
            end
          end

          # The variant name and content of an externally tagged enum.
          private def enum_value(value, variants)
            case value
            when String then variant = value
            when Hash
              raise Mismatch, "invalid value: map, expected map with a single key" unless value.size == 1

              variant, content = value.first
              content = [content]
            else mismatch(value, "string or map")
            end
            raise Mismatch, "unknown variant `#{variant}`, expected #{one_of(variants)}" unless variants.include?(variant)

            [variant, content]
          end

          # serde's OneOf list of variant names (de/mod.rs:2339-2352).
          private def one_of(variants)
            "one of #{variants.map { |name| "`#{name}`" }.join(', ')}"
          end

          # A unit variant's content: none, or null in an object.
          private def unit(content)
            return if content.nil? || content.first.nil?

            mismatch(content.first, "unit")
          end

          # A newtype variant's content, read by the block.
          private def newtype(content)
            raise Mismatch, "invalid type: unit variant, expected newtype variant" if content.nil?

            yield content.first
          end

          # A tuple variant's content: an array of strings of the variant's
          # length (value/de.rs:576-597, 195-211).
          private def tuple(content, variant)
            raise Mismatch, "invalid type: unit variant, expected tuple variant" if content.nil?

            items = content.first
            mismatch(items, "tuple variant") unless items.is_a?(Array)
            expected = "tuple variant MessageDialogButtons::#{variant}"
            raise Mismatch, "invalid type: null, expected #{expected}" if items.empty?

            length = TUPLES.fetch(variant)
            values = items.first(length).map { |item| string_value(item) }
            raise Mismatch, "invalid length #{items.size}, expected #{expected} with #{length} elements" if items.size < length
            raise Mismatch, "invalid length #{items.size}, expected fewer elements in array" if items.size > length

            values
          end

          private def picker_mode(value)
            variant, content = enum_value(value, PICKER_MODES)
            unit(content)
            PickerMode.constants.map { |name| PickerMode.const_get(name, false) }.find { |mode| mode.name == variant }
          end

          private def file_access_mode(value)
            variant, content = enum_value(value, FILE_ACCESS_MODES)
            unit(content)
            FileAccessMode.constants.map { |name| FileAccessMode.const_get(name, false) }.find { |mode| mode.name == variant }
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
