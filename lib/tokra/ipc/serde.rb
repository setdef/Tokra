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
    #   unknown_variant, unknown_field, missing_field; OneOf), src/de/impls.rs
    #   (the string, bool, f64 and tuple visitors); serde_derive src/de.rs
    #   (deserialize_seq), src/de/struct_.rs (visit_map),
    #   src/de/identifier.rs, src/de/enum_internally.rs; serde
    #   src/private/de.rs (TaggedContentVisitor); serde_json
    #   src/value/de.rs (deserialize_enum, visit_array_ref, the variant
    #   access)
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
    # They hold serde's concepts only. What a field or a variant means is
    # the caller's, and integers are CommandItem.integer's.
    #
    # === Example
    #
    #   Tokra::Ipc::Serde.unit_variant({ "Menu" => nil }, %w[Menu Submenu])  #=> "Menu"
    #   Tokra::Ipc::Serde.struct_fields([1, 2, 3], "Pair", %w[a b]) { |_field, raw| raw }
    #   # raises Mismatch: invalid length 3, expected fewer elements in array
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
      def self.struct_fields(value, name, fields, optional: [], deny_unknown: false, &read)
        case value
        when Hash then map_fields(value, fields, optional, deny_unknown, &read)
        when Array then seq_fields(value, name, fields, optional, &read)
        else raise CommandItem::Mismatch.invalid_type(value, "struct #{name}")
        end
      end

      # The elements of a Rust tuple of +size+, each read by the block,
      # which receives the element's index and its raw value. serde's
      # tuple visitor reads element by element, failing where the
      # sequence runs out (serde_core de/impls.rs:1411-1423), and
      # serde_json then rejects elements left over (value/de.rs:731-746,
      # 970-985).
      def self.tuple(value, size, &read)
        expecting = "a tuple of size #{size}"
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

      def self.map_fields(map, fields, optional, deny_unknown, &read)
        present = map.filter_map do |key, raw|
          if fields.include?(key)
            [key, field(key, raw, optional, &read)]
          elsif deny_unknown
            raise CommandItem::Mismatch, "unknown field `#{key}`, there are no fields" if fields.empty?

            raise CommandItem::Mismatch, "unknown field `#{key}`, expected #{one_of(fields)}"
          end
        end.to_h
        missing = fields.find { |key| !present.key?(key) && !optional.include?(key) }
        raise CommandItem::Mismatch, "missing field `#{missing}`" if missing

        fields.to_h { |key| [key, present[key]] }
      end
      private_class_method :map_fields

      def self.seq_fields(seq, name, fields, optional, &read)
        expecting = "struct #{name} with #{fields.size} #{(fields.size == 1) ? 'element' : 'elements'}"
        result = fields.each_with_index.to_h do |key, index|
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

      #--
      # SPDX-SnippetEnd
      #++
    end
  end
end
