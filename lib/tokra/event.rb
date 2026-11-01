# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Event, EventName, EmitArgs, and the event scripts adapted from
#                      tauri/crates/tauri/src/event/mod.rs and event/event_name.rs

module Tokra
  # An event that was emitted, as a Listener's handler receives it: the
  # id of the handler it triggered, and its payload as JSON text.
  #
  # Ruby and the page pass events to each other by name. Emitter#emit
  # sends one, Listener#listen hears one, and the page's +listen+ and
  # +emit+ from <tt>@tauri-apps/api/event</tt> take part in the same
  # exchange. The payload stays the JSON text it was sent as, so a handler
  # parses it as it needs.
  #
  # Mirrors Tauri's <tt>Event</tt> (event/mod.rs:141-162). Its EventId is
  # an Integer, a u32 in Tauri.
  #
  # === Example
  #
  #   app.listen("ready") { |event| JSON.parse(event.payload) }
  class Event < Data.define(:id, :payload)
    ##
    # :attr_reader: id
    # The id of the handler this event triggered, which Listener#unlisten
    # takes.

    ##
    # :attr_reader: payload
    # The payload, as JSON text.

    # Event names: the characters Tauri permits, and the errors for the
    # rest (event/event_name.rs).
    module Name # :nodoc:
      # Tauri's is_event_name_valid: Rust's char::is_alphanumeric, which
      # is Unicode's Alphabetic or Numeric, or '-', '/', ':', '_'
      # (event_name.rs:8-12).
      VALID = %r{\A(?:\p{Alphabetic}|\p{N}|[-/:_])*\z}

      # The message EventName's Deserialize impl fails with
      # (event_name.rs:57-70).
      DESERIALIZE_MESSAGE = "Event name must include only alphanumeric characters, `-`, `/`, `:` and `_`."

      # Whether +name+ is a valid event name.
      def self.valid?(name)
        VALID.match?(name)
      end

      # +name+, or Error::IllegalEventName when it is not valid, as
      # <tt>EventName::new</tt> answers (event_name.rs:19-26).
      def self.check(name)
        raise Error::IllegalEventName, name unless valid?(name)

        name
      end

      # The event name a command argument holds, read as EventName
      # deserializes (event_name.rs:57-70).
      def self.read(item)
        item.deserialize do |value|
          raise Ipc::CommandItem::Mismatch.invalid_type(value, "a string") unless value.is_a?(String)
          raise Ipc::CommandItem::Mismatch, DESERIALIZE_MESSAGE unless valid?(value)

          value
        end
      end
    end

    # An event's name and its payload already serialized, as Tauri's
    # EmitArgs holds them (event/mod.rs:112-139).
    class EmitArgs < Data.define(:event, :payload) # :nodoc:
      # The arguments for +payload+, serialized as serde_json serializes
      # it: a non-finite float becomes +null+.
      def self.serialize(event, payload)
        new(event:, payload: generate(payload))
      end

      def self.generate(value)
        JSON.generate(value)
      rescue JSON::GeneratorError
        finite = without_non_finite_floats(value)
        raise if finite == value

        JSON.generate(finite)
      end
      private_class_method :generate

      def self.without_non_finite_floats(value)
        case value
        when Float then value.finite? ? value : nil
        when Array then value.map { |item| without_non_finite_floats(item) }
        when Hash then value.transform_values { |item| without_non_finite_floats(item) }
        else value
        end
      end
      private_class_method :without_non_finite_floats
    end

    # The script that records a page listener in the listeners object
    # (event/mod.rs:164-188).
    def self.listen_js_script(listeners_object_name, serialized_target, event, event_id, handler) # :nodoc:
      render("listen.js.erb", listeners_object_name:, serialized_target:, event:, event_id:, handler_id: handler)
    end

    # The script that hands an event to the page's listeners with +ids+
    # (event/mod.rs:190-202).
    def self.emit_js_script(event_emit_function_name, emit_args, serialized_ids) # :nodoc:
      render("emit.js.erb", function_name: event_emit_function_name, event: emit_args.event,
        payload: emit_args.payload, ids: serialized_ids)
    end

    # The script that unregisters a page listener's callback, given the
    # JavaScript expressions for its event and id (event/mod.rs:204-218).
    def self.unlisten_js_script(listeners_object_name, event_arg, event_id_arg) # :nodoc:
      render("unlisten.js.erb", listeners_object_name:, event_arg:, event_id_arg:)
    end

    # The script that defines the page's emit function
    # (event/mod.rs:220-237).
    def self.event_initialization_script(function_name, listeners) # :nodoc:
      render("event_init.js.erb", function_name:, listeners:)
    end

    def self.render(name, values)
      ERB.new(Native.load_js_template(name)).result_with_hash(values)
    end
    private_class_method :render
  end
end

# SPDX-SnippetEnd
