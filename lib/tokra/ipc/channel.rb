# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Channel and JavaScriptChannelId adapted from
#                      tauri/crates/tauri/src/ipc/channel.rs

module Tokra
  module Ipc
    # A stream of messages from Ruby to a callback in the page.
    #
    # An invoke answers once. Some commands keep talking after that: a
    # download reports its progress, a global shortcut reports each press.
    # The page hands such a command a <tt>Channel</tt> from
    # <tt>@tauri-apps/api/core</tt>, which arrives as the string
    # <tt>__CHANNEL__:ID</tt>, and the command needs a way to call that
    # page's callback again and again, in order.
    #
    # A Channel is that way. Read one from an invoke with from_command, and
    # #send it any JSON value: the page's <tt>onmessage</tt> receives each
    # value, in the order you sent them, even when they cross threads. When
    # you are done with it, #drop it, and the page releases its callback.
    # A Channel serializes as its <tt>__CHANNEL__:ID</tt> string, so you
    # can hand it back to the page.
    #
    # Mirrors Tauri's <tt>ipc::Channel</tt> (channel.rs:48-298). Tauri
    # fetches messages of 8 KiB or more through a command of its own; Tokra
    # evaluates every message, and the page receives the same value
    # (Plan 025, decision 5). Raw byte messages are not ported, since
    # Tokra's IPC bodies are JSON only (ADR 010).
    #
    # === Examples
    #
    #   # In a plugin's extend_api:
    #   channel = Tokra::Ipc::Channel.from_command(invoke, "onProgress")
    #   Thread.new do
    #     10.times { |step| channel.send({ "done" => step * 10 }) }
    #     channel.drop
    #   end
    #   invoke.resolve(nil)
    #
    #   # A channel whose messages Ruby handles itself:
    #   channel = Tokra::Ipc::Channel.new { |json| puts json }
    #   channel.send([1, 2, 3])  # prints [1,2,3]
    class Channel
      # The prefix of a channel's string form (channel.rs:28).
      IPC_PAYLOAD_PREFIX = "__CHANNEL__:"

      # The name of Tauri's channel plugin (channel.rs:30).
      CHANNEL_PLUGIN_NAME = "__TAURI_CHANNEL__"

      @counter = 0
      @counter_lock = Thread::Mutex.new

      class << self
        # The channel the frontend passed as argument +key+ of +invoke+,
        # sending to the page that invoked it.
        #
        # Raises ArgumentError with Tauri's message when the argument is
        # missing or not a string (CommandItem), or when the string is not
        # <tt>__CHANNEL__:</tt> and an id. Mirrors the CommandArg impl
        # for Channel (channel.rs:300-316).
        #
        # === Example
        #
        #   channel = Tokra::Ipc::Channel.from_command(invoke, "handler")
        def from_command(invoke, key)
          value = CommandItem.new(name: invoke.command, key:, payload: invoke.payload).string
          id = begin
            JavaScriptChannelId.from_str(value)
          rescue ArgumentError
            raise ArgumentError, "invalid channel value `#{value}`, expected a string in the `#{IPC_PAYLOAD_PREFIX}ID` format"
          end
          id.channel_on(invoke.webview)
        end

        # A channel with +id+ that hands each message's JSON to
        # +on_message+ and calls +on_drop+ when dropped (channel.rs:223-241).
        def new_with_id(id, on_message, on_drop) # :nodoc:
          channel = allocate
          channel.__send__(:setup, id, on_message, on_drop)
          channel
        end

        # The next id from the process-wide counter (channel.rs:41).
        private def next_id
          @counter_lock.synchronize { (@counter += 1) - 1 }
        end
      end

      # The channel's id: the page's callback id for a channel from the
      # page, a counter for one made with Channel.new (channel.rs:286-289).
      attr_reader :id

      # Creates a channel whose messages go to the block, as JSON text
      # (channel.rs:211-221). Its id comes from a counter of its own.
      #
      # === Example
      #
      #   channel = Tokra::Ipc::Channel.new { |json| log << json }
      def initialize(&on_message)
        raise ArgumentError, "Channel.new needs a block for its messages" unless on_message

        setup(Channel.__send__(:next_id), on_message, nil)
      end

      # Sends +data+, any JSON value, through the channel and returns +nil+.
      #
      # Non-finite floats become +null+, as serde_json writes them. A
      # channel from the page evaluates its callback in the webview, which
      # from another thread travels to the main thread; messages keep the
      # order you sent them in. A send after #drop does nothing, as Rust
      # cannot send through a channel it has dropped (channel.rs:80-86).
      # Mirrors <tt>Channel::send</tt> (channel.rs:291-297).
      #
      # === Example
      #
      #   channel.send({ "shortcut" => "F19", "state" => "Pressed" })
      def send(data)
        json = serialize(data)
        @mutex.synchronize { @on_message.call(json) unless @dropped }
        nil
      end

      # Ends the channel: a channel from the page tells it no more
      # messages come, so the page releases its callback. Later calls, and
      # later sends, do nothing; a send under way finishes first, so the
      # end always comes after the last message. Rust does this when the last copy of the channel is
      # dropped; Ruby frees objects only when the garbage collector runs,
      # so the code that holds the channel last calls this (Plan 025,
      # decision 5). Returns +nil+.
      #
      # === Example
      #
      #   channel.drop
      def drop
        @mutex.synchronize do
          next if @dropped

          @dropped = true
          @on_drop&.call
        end
        nil
      end

      # The channel's string form, <tt>__CHANNEL__:ID</tt>, as JSON, so a
      # channel inside a value serializes as Tauri's does (channel.rs:88-95).
      #
      # === Example
      #
      #   JSON.generate({ "onEvent" => channel })  #=> "{\"onEvent\":\"__CHANNEL__:5\"}"
      def to_json(*)
        "#{IPC_PAYLOAD_PREFIX}#{@id}".to_json(*)
      end

      private def setup(id, on_message, on_drop)
        @id = id
        @on_message = on_message
        @on_drop = on_drop
        @dropped = false
        @mutex = Thread::Mutex.new
      end

      # JSON text for +data+, with non-finite floats as +null+, as
      # Invoke#resolve serializes.
      private def serialize(data)
        JSON.generate(data)
      rescue JSON::GeneratorError
        finite = without_non_finite_floats(data)
        raise if finite == data

        JSON.generate(finite)
      end

      private def without_non_finite_floats(data)
        case data
        when Float then data.finite? ? data : nil
        when Array then data.map { |item| without_non_finite_floats(item) }
        when Hash then data.transform_values { |item| without_non_finite_floats(item) }
        else data
        end
      end
    end

    # The id of a channel the page made, read from its
    # <tt>__CHANNEL__:ID</tt> string.
    #
    # A command usually takes its channel as a top-level argument, which
    # Channel.from_command reads. When the channel sits inside a larger
    # argument, such as an object with an +onClick+ field, read its string
    # with this class and turn it into a Channel for the page with
    # #channel_on.
    #
    # Mirrors Tauri's <tt>ipc::JavaScriptChannelId</tt> (channel.rs:97-195);
    # +callback+ is the page's callback id, Tauri's <tt>CallbackFn</tt>.
    #
    # === Example
    #
    #   id = Tokra::Ipc::JavaScriptChannelId.from_str(invoke.payload["button"]["onClick"])
    #   id.channel_on(invoke.webview).send("clicked")
    class JavaScriptChannelId < Data.define(:callback)
      # :attr_reader: callback
      # The page's callback id, an Integer that fits a u32.

      # The id in +string+, <tt>__CHANNEL__:</tt> and a u32. Raises
      # ArgumentError with Tauri's <tt>invalid channel string</tt> when
      # the prefix is missing and <tt>invalid channel ID</tt> when the rest
      # is not a u32, read as Rust reads one: an optional +, then ASCII
      # digits (channel.rs:121-130). These are FromStr's messages; Tauri's
      # Deserialize, which reads the id inside a larger argument, replaces
      # both with <tt>invalid channel value `VALUE`, expected a string in
      # the `__CHANNEL__:ID` format</tt> (channel.rs:197-209), the message
      # Channel.from_command raises.
      #
      # === Example
      #
      #   Tokra::Ipc::JavaScriptChannelId.from_str("__CHANNEL__:7").callback  #=> 7
      def self.from_str(string)
        raise ArgumentError, "invalid channel string" unless string.start_with?(Channel::IPC_PAYLOAD_PREFIX)

        digits = string.delete_prefix(Channel::IPC_PAYLOAD_PREFIX)
        raise ArgumentError, "invalid channel ID" unless digits.match?(/\A\+?[0-9]+\z/)

        id = Integer(digits.delete_prefix("+"), 10)
        raise ArgumentError, "invalid channel ID" if id > 0xFFFF_FFFF

        new(callback: id)
      end

      # A Channel that sends to this callback in +webview+.
      #
      # Each message evaluates <tt>runCallback(ID, { message: JSON, index:
      # N })</tt>, counting N from zero, so the page's Channel puts them in
      # order; Channel#drop evaluates <tt>{ end: true, index: N }</tt>.
      # Tauri also lets an app intercept channel messages; Tokra has no
      # interceptor yet. Mirrors <tt>JavaScriptChannelId::channel_on</tt>
      # (channel.rs:134-194).
      #
      # === Example
      #
      #   channel = id.channel_on(invoke.webview)
      def channel_on(webview)
        callback_id = callback
        counter = 0
        lock = Thread::Mutex.new
        on_message = lambda do |json|
          index = lock.synchronize { (counter += 1) - 1 }
          webview.eval(FormatCallback.format_raw_js(callback_id, "{ message: #{json}, index: #{index} }"))
        end
        on_drop = lambda do
          index = lock.synchronize { counter }
          webview.eval(FormatCallback.format_raw_js(callback_id, "{ end: true, index: #{index} }"))
        rescue Tokra::Error
          nil
        end
        Channel.new_with_id(callback_id, on_message, on_drop)
      end
    end
  end
end

# SPDX-SnippetEnd
