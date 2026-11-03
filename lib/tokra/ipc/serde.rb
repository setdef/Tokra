# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Ipc
    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
    # SPDX-SnippetComment: serde 1.0.228's visitors as serde_json 1.0.145's
    #   &Value drives them: serde_core src/de/mod.rs (Error::invalid_length,
    #   unknown_variant, unknown_field, missing_field, duplicate_field;
    #   OneOf), src/de/impls.rs (the string, bool, f64 and tuple visitors);
    #   serde_derive src/de.rs (deserialize_seq, expr_is_missing,
    #   expr_is_missing_seq), src/de/struct_.rs (visit_map, FIELDS),
    #   src/de/identifier.rs, src/de/enum_internally.rs,
    #   src/de/enum_untagged.rs, src/de/enum_adjacently.rs,
    #   src/internals/attr.rs and src/internals/name.rs (aliases); serde
    #   src/private/de.rs (TaggedContentVisitor, TagOrContentFieldVisitor,
    #   TagContentOtherFieldVisitor, UntaggedUnitVisitor,
    #   AdjacentlyTaggedEnumVariantSeed); serde_json src/value/de.rs
    #   (deserialize_enum, visit_array_ref, the variant access)
    #++

    # serde's visitors, as serde_json's Value drives them.
    #
    # A Tauri command's argument types derive +Deserialize+, and serde
    # reads each one from the invoke's JSON with fixed rules and fixed
    # words: an externally tagged enum is a string or a one-key map, a
    # struct is a map read in its key order or a sequence read element by
    # element, and every failure has its message. Tauri's CommandItem hands
    # serde a <tt>&Value</tt> (ipc/command.rs:73-105), so the citations
    # here are serde_json's <tt>&Value</tt> impls. A map's key order is
    # the Hash's, which Ipc::Json sorts as serde_json's BTreeMap orders
    # keys (json.rb:274-276); Tauri does not enable serde_json's
    # preserve_order. These functions are
    # those rules, for the plugins that read the page's arguments. Each
    # raises CommandItem::Mismatch with serde's words, which
    # CommandItem#deserialize turns into the argument's InvalidArgs.
    #
    # Tauri's config types take more of serde's forms than its command
    # arguments do: fields with aliases and defaults, untagged enums tried
    # variant by variant, and adjacently tagged ones. Tauri reads the
    # config the same way, a Value handed to serde_json::from_value
    # (tauri-codegen lib.rs:80-93), so these functions read it too, with
    # the same words (plan 054).
    #
    # They hold serde's concepts only. What a field or a variant means is
    # the caller's, and integers are CommandItem.integer's.
    #
    # === Examples
    #
    #   Tokra::Ipc::Serde.unit_variant({ "Menu" => nil }, %w[Menu Submenu])  #=> "Menu"
    #   Tokra::Ipc::Serde.struct_fields([1, 2, 3], "Pair", %w[a b]) { |_field, raw| raw }
    #   # raises Mismatch: invalid length 3, expected fewer elements in array
    #
    #   Tokra::Ipc::Serde.struct_fields({ "icon-path" => "tray.png" }, "TrayIconConfig", %w[iconPath iconAsTemplate],
    #                                   aliases: { "iconPath" => ["icon-path"] },
    #                                   defaults: { "iconAsTemplate" => false }) { |_field, raw| raw }
    #   #=> {"iconPath" => "tray.png", "iconAsTemplate" => false}
    #
    #   Tokra::Ipc::Serde.untagged(1, "PreventOverflowConfig", [->(raw) { Tokra::Ipc::Serde.boolean(raw) }])
    #   # raises Mismatch: data did not match any variant of untagged enum PreventOverflowConfig
    module Serde # :nodoc:
      # The variant +name+, or serde's +unknown_variant+ error, its list
      # worded as serde's OneOf words it (serde_core de/mod.rs:252-265,
      # 2333-2355).
      def self.known_variant(name, variants)
        return name if variants.include?(name)
        raise CommandItem::Mismatch, "unknown variant `#{name}`, there are no variants" if variants.empty?

        raise CommandItem::Mismatch, "unknown variant `#{name}`, expected #{one_of(variants)}"
      end

      # The variant of an enum of unit variants: a string, or a map of the
      # one variant to +null+, as serde_json reads it.
      def self.unit_variant(value, variants)
        enum_variant(value, variants).first
      end

      # The variant and content of an externally tagged enum of unit and
      # newtype variants, as serde_json's +deserialize_enum+ for
      # <tt>&Value</tt> reads it (value/de.rs:770-800, 857-876): a string
      # names a variant with no content, and a one-key map a variant and
      # its content. The variants in +newtype+ carry content, which a bare
      # string lacks; the others are unit variants, whose content must be
      # +null+ (value/de.rs:1066-1083).
      # The content is +nil+ for a unit variant.
      def self.enum_variant(value, variants, newtype: [])
        case value
        when String
          variant = known_variant(value, variants)
          raise CommandItem::Mismatch, "invalid type: unit variant, expected newtype variant" if newtype.include?(variant)

          [variant, nil]
        when Hash
          raise CommandItem::Mismatch, "invalid value: map, expected map with a single key" unless value.size == 1

          name, content = value.first #: [String, json_value]
          variant = known_variant(name, variants)
          return [variant, content] if newtype.include?(variant)
          raise CommandItem::Mismatch.invalid_type(content, "unit") unless content.nil?

          [variant, nil]
        else raise CommandItem::Mismatch.invalid_type(value, "string or map")
        end
      end

      # The variant and the rest of an internally tagged enum, as serde's
      # TaggedContentVisitor reads it (serde private/de.rs:816-886): the
      # +tag+ key of a map, read as a variant identifier when it is
      # reached, and the map without it; or a sequence's first element,
      # and the elements after it. +enum_name+ names the enum in the
      # error for anything else (serde_derive de/enum_internally.rs:46).
      def self.internally_tagged(value, tag, enum_name, variants)
        case value
        when Hash
          raise CommandItem::Mismatch, "missing field `#{tag}`" unless value.key?(tag)

          [variant_identifier(value[tag], variants), value.except(tag)]
        when Array
          raise CommandItem::Mismatch, "missing field `#{tag}`" if value.empty?

          [variant_identifier(value.first, variants), value.drop(1)]
        else raise CommandItem::Mismatch.invalid_type(value, "internally tagged enum #{enum_name}")
        end
      end

      # The fields of the struct +name+, each read by the block, which
      # receives the field's name and its raw value and answers the
      # field's value. Answers a Hash of each field to its value.
      #
      # From a map, as serde's derived +visit_map+ reads one: each key in
      # the Hash's order (Ipc::Json sorts it as serde_json's BTreeMap
      # does, json.rb:274-276; Tauri has no preserve_order), a field's
      # value read when it is reached and any
      # other key ignored, or with +deny_unknown+ rejected; then the first
      # missing field, in +fields+' order (serde_derive de/struct_.rs). From
      # a sequence, as the derived +visit_seq+ reads one: element by
      # element, failing where the sequence runs out (serde_derive
      # de.rs:450-505), then serde_json's error for elements left over
      # (value/de.rs:731-746).
      #
      # The fields in +optional+ are Rust +Option+s: +null+ reads as +nil+
      # without the block, and a map without one reads it as +nil+. A
      # sequence must reach it all the same.
      #
      # +aliases+ gives a field its other names, <tt>#[serde(alias)]</tt>:
      # a key reads the field by any of them, and a second key for a field
      # already read is serde's <tt>duplicate field</tt>, by the field's
      # name (de/struct_.rs:262-272). The unknown-field error lists each
      # field's names, the name among them, in byte order, field by field
      # in +fields+' order: serde_derive's FIELDS holds each field's
      # names as a BTreeSet (de/struct_.rs:55-64, 120-127;
      # internals/attr.rs:1270-1286; internals/name.rs:71-75).
      #
      # +defaults+ gives the value of a field with <tt>#[serde(default)]</tt>
      # or <tt>default = "..."</tt>, or of any field when the struct has
      # one, already read: what the block would answer. A map without the
      # field reads it (de.rs:763-786), and so does a sequence that runs
      # out before the field (de.rs:805-836), where a field without one,
      # an +optional+ one too, fails.
      def self.struct_fields(value, name, fields, optional: [], deny_unknown: false, aliases: {}, defaults: {}, &read)
        case value
        when Hash then map_fields(value, fields, optional, deny_unknown, aliases, defaults, &read)
        when Array then seq_fields(value, name, fields, optional, defaults, &read)
        else raise CommandItem::Mismatch.invalid_type(value, "struct #{name}")
        end
      end

      # The fields of the struct variant +name+ (<tt>"Enum::Variant"</tt>)
      # of an untagged or adjacently tagged enum, as #struct_fields reads a
      # map's, with the same keywords. serde_derive gives that form no
      # +visit_seq+ (de/struct_.rs:70-73), so anything but a map is the
      # wrong type, a sequence too.
      def self.untagged_struct_variant(value, name, fields, optional: [], deny_unknown: false, aliases: {}, defaults: {},
        &read
      )
        raise CommandItem::Mismatch.invalid_type(value, "struct variant #{name}") unless value.is_a?(Hash)

        map_fields(value, fields, optional, deny_unknown, aliases, defaults, &read)
      end

      # The unit variant +name+ (<tt>"Enum::Variant"</tt>) of an untagged or
      # adjacently tagged enum: +nil+ from +null+, and serde's error for
      # anything else (serde private/de.rs:3002-3040, UntaggedUnitVisitor).
      # serde names the variant by its Rust name, not its renamed one
      # (de/enum_untagged.rs:80-89).
      def self.untagged_unit(value, name)
        raise CommandItem::Mismatch.invalid_type(value, "unit variant #{name}") unless value.nil?
      end

      # The value of the untagged enum +name+: the first of +readers+, one
      # per variant in declaration order, that reads +value+ without a
      # Mismatch, or serde's error when none does (de/enum_untagged.rs:22-58).
      # Only a Mismatch passes to the next variant; any other error is a
      # bug, and propagates. A struct variant's reader calls
      # #untagged_struct_variant, a unit variant's #untagged_unit.
      def self.untagged(value, name, readers)
        readers.each do |reader|
          return reader.call(value)
        rescue CommandItem::Mismatch
          next
        end
        raise CommandItem::Mismatch, "data did not match any variant of untagged enum #{name}"
      end

      # The variant and content of the adjacently tagged enum +enum_name+,
      # <tt>#[serde(tag = "...", content = "...")]</tt>, as serde_derive
      # reads one (de/enum_adjacently.rs:18-323). The block receives the
      # variant and its raw content and answers the content's value; a unit
      # variant's block calls #untagged_unit, a struct variant's
      # #untagged_struct_variant. Answers the variant and that value.
      #
      # From a map, in the Hash's order: the +tag+ key, read as
      # serde_json reads a unit variant (#unit_variant; private/de.rs:3449-3500),
      # and the +content+ key, in either order; with the content first it
      # is read once the tag is known. Without +deny_unknown+ any other key
      # is stepped over; with it, any other key is serde's invalid value
      # (private/de.rs:898-975). A map without the tag is
      # <tt>missing field</tt>, and so is one without the content, unless
      # the variant is in +unit+, which then reads +nil+ without the block.
      # serde also lets a newtype variant go without its content when the
      # content's type reads a missing field, as an +Option+ does
      # (private::de::missing_field, de/enum_adjacently.rs:63-101); that is
      # not modelled, since no adjacently tagged enum in Tauri's config
      # has such a variant.
      #
      # From a sequence: the tag, read as a variant identifier, then the
      # content, which every variant needs here, then serde_json's error
      # for elements left over.
      def self.adjacently_tagged(value, tag, content, enum_name, variants, unit: [], deny_unknown: false, &read)
        case value
        when Hash then adjacent_map(value, tag, content, variants, unit, deny_unknown, &read)
        when Array then adjacent_seq(value, enum_name, variants, &read)
        else raise CommandItem::Mismatch.invalid_type(value, "adjacently tagged enum #{enum_name}")
        end
      end

      # The elements of a Rust tuple of +size+, each read by the block,
      # which receives the element's index and its raw value. serde's
      # tuple visitor reads element by element, failing where the
      # sequence runs out (serde_core de/impls.rs:1411-1423), and
      # serde_json then rejects elements left over (value/de.rs:731-746,
      # 970-985).
      #
      # A Rust array of +size+ reads the same way, with its own words:
      # pass <tt>expecting: "an array of length 16"</tt> for a
      # <tt>[T; 16]</tt> (de/impls.rs:1268-1292).
      def self.tuple(value, size, expecting: "a tuple of size #{size}", &read)
        raise CommandItem::Mismatch.invalid_type(value, expecting) unless value.is_a?(Array)

        elements = Array.new(size) do |index|
          raise CommandItem::Mismatch, "invalid length #{index}, expected #{expecting}" if index >= value.size

          read.call(index, value[index])
        end
        raise CommandItem::Mismatch, "invalid length #{value.size}, expected fewer elements in array" if value.size > size

        elements
      end

      # +value+ as a Rust +String+ (serde_core de/impls.rs, StringVisitor).
      def self.string(value)
        value.is_a?(String) ? value : raise(CommandItem::Mismatch.invalid_type(value, "a string"))
      end

      # +value+ as a Rust <tt>&str</tt> (serde_core de/impls.rs, StrVisitor).
      def self.borrowed_str(value)
        value.is_a?(String) ? value : raise(CommandItem::Mismatch.invalid_type(value, "a borrowed string"))
      end

      # +value+ as a Rust +bool+ (serde_core de/impls.rs, BoolVisitor).
      def self.boolean(value)
        case value
        when true, false then value
        else raise CommandItem::Mismatch.invalid_type(value, "a boolean")
        end
      end

      # +value+ as a Rust +f64+: serde's f64 visitor takes an integer or a
      # float, and rejects anything else (serde_core de/impls.rs).
      def self.f64(value)
        case value
        when Integer, Float then Float(value)
        else raise CommandItem::Mismatch.invalid_type(value, "f64")
        end
      end

      # +names+ as serde's OneOf lists them (serde_core de/mod.rs:2333-2355).
      def self.one_of(names)
        quoted = names.map { |name| "`#{name}`" }
        case quoted.size
        when 1 then quoted.first.to_s
        when 2 then quoted.join(" or ")
        else "one of #{quoted.join(', ')}"
        end
      end
      private_class_method :one_of

      # The variant +tag+ names, as a derived variant identifier reads
      # serde_json's <tt>&Value</tt>: only from a string (value/de.rs:1025-1030,
      # 918-926;
      # serde_derive de/identifier.rs:221).
      def self.variant_identifier(tag, variants)
        raise CommandItem::Mismatch.invalid_type(tag, "variant identifier") unless tag.is_a?(String)

        known_variant(tag, variants)
      end
      private_class_method :variant_identifier

      def self.map_fields(map, fields, optional, deny_unknown, aliases, defaults, &read)
        names = fields.to_h { |key| [key, [key, *aliases.fetch(key, [])].uniq.sort] }
        owners = names.flat_map { |key, all| all.map { |alias_name| [alias_name, key] } }.to_h
        read_keys = [] #: Array[String]
        present = map.filter_map do |name, raw|
          key = owners[name]
          if key
            raise CommandItem::Mismatch, "duplicate field `#{key}`" if read_keys.include?(key)

            read_keys << key
            [key, field(key, raw, optional, &read)]
          elsif deny_unknown
            raise CommandItem::Mismatch, "unknown field `#{name}`, there are no fields" if fields.empty?

            raise CommandItem::Mismatch, "unknown field `#{name}`, expected #{one_of(names.values.flatten)}"
          end
        end.to_h
        missing = fields.find { |key| !present.key?(key) && !optional.include?(key) && !defaults.key?(key) }
        raise CommandItem::Mismatch, "missing field `#{missing}`" if missing

        fields.to_h { |key| [key, present.fetch(key) { defaults[key] }] }
      end
      private_class_method :map_fields

      def self.seq_fields(seq, name, fields, optional, defaults, &read)
        expecting = "struct #{name} with #{fields.size} #{(fields.size == 1) ? 'element' : 'elements'}"
        result = fields.each_with_index.to_h do |key, index|
          next [key, defaults.fetch(key)] if index >= seq.size && defaults.key?(key)
          raise CommandItem::Mismatch, "invalid length #{index}, expected #{expecting}" if index >= seq.size

          [key, field(key, seq[index], optional, &read)]
        end
        raise CommandItem::Mismatch, "invalid length #{seq.size}, expected fewer elements in array" if seq.size > fields.size

        result
      end
      private_class_method :seq_fields

      def self.field(key, raw, optional)
        (raw.nil? && optional.include?(key)) ? nil : yield(key, raw)
      end
      private_class_method :field

      # visit_map of an adjacently tagged enum (de/enum_adjacently.rs:222-278).
      # A Hash holds each key once, so the duplicate-key arms cannot arise;
      # the keys after the tag and the content are still visited, so
      # +deny_unknown+ refuses one there.
      def self.adjacent_map(map, tag, content, variants, unit, deny_unknown, &read)
        keys = AdjacentKeys.new(map.keys, tag, content, deny_unknown)
        first = keys.next_relevant
        raise CommandItem::Mismatch, "missing field `#{tag}`" if first.nil?

        if first == :tag
          variant = unit_variant(map[tag], variants)
          unless keys.next_relevant
            raise CommandItem::Mismatch, "missing field `#{content}`" unless unit.include?(variant)

            return [variant, nil]
          end
        else
          # The content came first: serde buffers it until the tag is read.
          raise CommandItem::Mismatch, "missing field `#{tag}`" unless keys.next_relevant

          variant = unit_variant(map[tag], variants)
        end
        result = read.call(variant, map[content])
        keys.next_relevant
        [variant, result]
      end
      private_class_method :adjacent_map

      # visit_seq of an adjacently tagged enum (de/enum_adjacently.rs:280-308),
      # then serde_json's check for elements left over (value/de.rs:731-746).
      def self.adjacent_seq(seq, enum_name, variants)
        expecting = "adjacently tagged enum #{enum_name}"
        raise CommandItem::Mismatch, "invalid length 0, expected #{expecting}" if seq.empty?

        variant = variant_identifier(seq.first, variants)
        raise CommandItem::Mismatch, "invalid length 1, expected #{expecting}" if seq.size < 2

        result = yield(variant, seq[1])
        raise CommandItem::Mismatch, "invalid length #{seq.size}, expected fewer elements in array" if seq.size > 2

        [variant, result]
      end
      private_class_method :adjacent_seq

      # An adjacently tagged enum's map keys, visited one at a time as
      # serde's next_relevant_key visits them (de/enum_adjacently.rs:105-165):
      # the tag, the content, or none left, stepping over any other key, or
      # with +deny_unknown+ refusing it as TagOrContentFieldVisitor does
      # (private/de.rs:918-962).
      class AdjacentKeys # :nodoc:
        def initialize(keys, tag, content, deny_unknown)
          @keys = keys
          @tag = tag
          @content = content
          @deny_unknown = deny_unknown
          @position = 0
        end

        # +:tag+, +:content+, or +nil+ when no key is left.
        def next_relevant
          while @position < @keys.size
            key = @keys.fetch(@position)
            @position += 1
            return :tag if key == @tag
            return :content if key == @content
            next unless @deny_unknown

            raise CommandItem::Mismatch,
              "invalid value: #{Unexpected.describe(key)}, expected #{Unexpected.debug(@tag)} or #{Unexpected.debug(@content)}"
          end
          nil
        end
      end

      #--
      # SPDX-SnippetEnd
      #++
    end
  end
end
