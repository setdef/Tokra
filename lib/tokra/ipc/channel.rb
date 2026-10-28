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
    # #send it any JSON value, or bytes in a Response: the page's
    # <tt>onmessage</tt> receives each value, bytes as an ArrayBuffer (a
    # number array when a large message was fetched after the client fell
    # back from <tt>ipc://</tt> to <tt>postMessage</tt>, as in Tauri), in
    # the order you sent them, even when they cross threads. When you are
    # done with it, #drop it, and the page releases its callback. A
    # Channel serializes as its <tt>__CHANNEL__:ID</tt> string, so you can
    # hand it back to the page.
    #
    # Small messages are evaluated in the page. JSON of 8 KiB or more, and
    # bytes of 1 KiB or more, wait in the app's ChannelDataIpcQueue until
    # the page fetches them with <tt>plugin:__TAURI_CHANNEL__|fetch</tt>
    # over <tt>ipc://</tt>, which carries them faster than a script can.
    # Data the page never fetches, because it reloaded first, stays queued
    # until the app exits, as in Tauri.
    #
    # Mirrors Tauri's <tt>ipc::Channel</tt> (channel.rs:28-346).
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
    #   # Bytes arrive in the page as an ArrayBuffer:
    #   channel.send(Tokra::Ipc::Response.new(File.binread("chunk.bin")))
    #
    #   # A channel whose messages Ruby handles itself:
    #   channel = Tokra::Ipc::Channel.new { |body| puts body }
    #   channel.send([1, 2, 3])  # prints [1,2,3]
    class Channel
      # The prefix of a channel's string form (channel.rs:28).
      IPC_PAYLOAD_PREFIX = "__CHANNEL__:"

      # The name of Tauri's channel plugin (channel.rs:30).
      CHANNEL_PLUGIN_NAME = "__TAURI_CHANNEL__"

      # The command the page fetches queued channel data with
      # (channel.rs:32).
      FETCH_CHANNEL_DATA_COMMAND = "plugin:__TAURI_CHANNEL__|fetch"

      # The header that names the data to fetch (channel.rs:33).
      CHANNEL_ID_HEADER_NAME = "Tauri-Channel-Id"

      # JSON shorter than this many bytes is evaluated, longer is fetched
      # (channel.rs:35-37).
      MAX_JSON_DIRECT_EXECUTE_THRESHOLD = 8192

      # Bytes fewer than this are evaluated, more are fetched
      # (channel.rs:38-39).
      MAX_RAW_DIRECT_EXECUTE_THRESHOLD = 1024

      private_constant :CHANNEL_ID_HEADER_NAME, :MAX_JSON_DIRECT_EXECUTE_THRESHOLD,
        :MAX_RAW_DIRECT_EXECUTE_THRESHOLD

      @counter = 0
      @data_counter = 0
      @counter_lock = Thread::Mutex.new

      class << self
        # The channel the frontend passed as argument +key+ of +invoke+,
        # sending to the page that invoked it.
        #
        # Raises Tokra::Error::InvalidArgs with Tauri's message when the
        # argument is missing or not a string (CommandItem), and
        # InvokeError when the string is not <tt>__CHANNEL__:</tt> and an
        # id. Mirrors the CommandArg impl for Channel (channel.rs:300-316).
        #
        # === Example
        #
        #   channel = Tokra::Ipc::Channel.from_command(invoke, "handler")
        def from_command(invoke, key)
          value = CommandItem.new(name: invoke.command, key:, payload: invoke.body).string
          id = begin
            JavaScriptChannelId.from_str(value)
          rescue ArgumentError
            raise InvokeError, "invalid channel value `#{value}`, expected a string in the `#{IPC_PAYLOAD_PREFIX}ID` format"
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

        # A channel that answers an invoke's +callback+ in +webview+: the
        # message itself is the callback's argument. The postMessage
        # responder sends results through it off macOS
        # (ipc/protocol.rs:371-407). Mirrors
        # <tt>Channel::from_callback_fn</tt> (channel.rs:243-284).
        def from_callback_fn(webview, callback) # :nodoc:
          on_message = lambda do |body|
            deliver(webview, body,
              inline: -> (js) { FormatCallback.format_raw_js(callback, js) },
              fetched: "window.__TAURI_INTERNALS__.runCallback(#{callback}, response)")
          end
          new_with_id(callback, on_message, nil)
        end

        # Evaluates +body+ in +webview+ by the path Tauri picks for its
        # size (channel.rs:153-182): +inline+ wraps the JSON or the
        # ArrayBuffer expression of a small message; a large one is queued
        # and fetched, and +fetched+ is the script that receives the
        # fetch's +response+.
        private def deliver(webview, body, inline:, fetched:)
          raw = InvokeBody.raw?(body)
          if !raw && body.bytesize < MAX_JSON_DIRECT_EXECUTE_THRESHOLD
            webview.eval(inline.call(body))
          elsif raw && body.bytesize < MAX_RAW_DIRECT_EXECUTE_THRESHOLD
            webview.eval(inline.call("new Uint8Array(#{JSON.generate(body.bytes)}).buffer"))
          else
            data_id = next_data_id
            queue = webview.state(ChannelDataIpcQueue) #: ChannelDataIpcQueue
            queue.insert(data_id, body)
            webview.eval(
              "window.__TAURI_INTERNALS__.invoke('#{FETCH_CHANNEL_DATA_COMMAND}', null, " \
                "{ headers: { '#{CHANNEL_ID_HEADER_NAME}': '#{data_id}' } }).then((response) => #{fetched}).catch(console.error)"
            )
          end
        end

        # The next id from the process-wide counter (channel.rs:41).
        private def next_id
          @counter_lock.synchronize { (@counter += 1) - 1 }
        end

        # The next data id, from a process-wide counter that wraps at
        # 2^32, as <tt>AtomicU32::fetch_add</tt> does (channel.rs:42, 169).
        private def next_data_id
          @counter_lock.synchronize do
            id = @data_counter
            @data_counter = (id + 1) & 0xFFFF_FFFF
            id
          end
        end
      end

      # The channel's id: the page's callback id for a channel from the
      # page, a counter for one made with Channel.new (channel.rs:286-289).
      attr_reader :id

      # Creates a channel whose messages go to the block, each as its body
      # String: UTF-8 JSON text, or a binary String for bytes sent in a
      # Response (channel.rs:211-221). Its id comes from a counter of its
      # own.
      #
      # === Example
      #
      #   channel = Tokra::Ipc::Channel.new { |body| log << body }
      def initialize(&on_message)
        raise ArgumentError, "Channel.new needs a block for its messages" unless on_message

        setup(Channel.__send__(:next_id), on_message, nil)
      end

      # Sends +data+ through the channel and returns +nil+.
      #
      # +data+ is any JSON value, or a Response, whose body is sent as it
      # is: bytes for a binary String, JSON text otherwise, as Tauri's
      # <tt>IpcResponse</tt> impls give them (ipc/mod.rs:181-198). A binary
      # String outside a Response is serialized like any other value, as
      # Invoke#resolve does. Non-finite floats become +null+, as serde_json
      # writes them. A
      # channel from the page evaluates its callback in the webview, which
      # from another thread travels to the main thread; messages keep the
      # order you sent them in. A send after #drop does nothing, as Rust
      # cannot send through a channel it has dropped (channel.rs:80-86).
      # Mirrors <tt>Channel::send</tt> (channel.rs:291-297).
      #
      # === Example
      #
      #   channel.send({ "shortcut" => "F19", "state" => "Pressed" })
      #   channel.send(Tokra::Ipc::Response.new("\x89PNG".b))
      def send(data)
        body = data.is_a?(Response) ? data.body : serialize(data)
        @mutex.synchronize { @on_message.call(body) unless @dropped }
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
      def to_json(state = nil)
        text = "#{IPC_PAYLOAD_PREFIX}#{@id}"
        state ? text.to_json(state) : text.to_json
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
      # Each message reaches <tt>runCallback(ID, { message: VALUE, index:
      # N })</tt>, counting N from zero, so the page's Channel puts them in
      # order: evaluated when small, fetched when large (Channel). A
      # fetched message may land after later ones; the page waits for it.
      # Channel#drop evaluates <tt>{ end: true, index: N }</tt>, which the
      # page also holds until every earlier message is in. Tauri also lets
      # an app intercept channel messages; Tokra has no interceptor yet.
      # Mirrors <tt>JavaScriptChannelId::channel_on</tt>
      # (channel.rs:134-194).
      #
      # === Example
      #
      #   channel = id.channel_on(invoke.webview)
      def channel_on(webview)
        callback_id = callback
        counter = 0
        lock = Thread::Mutex.new
        on_message = lambda do |body|
          index = lock.synchronize { (counter += 1) - 1 }
          Channel.__send__(:deliver, webview, body,
            inline: -> (js) { FormatCallback.format_raw_js(callback_id, "{ message: #{js}, index: #{index} }") },
            fetched: "window.__TAURI_INTERNALS__.runCallback(#{callback_id}, { message: response, index: #{index} })")
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

    # The data channels wait to send until the page fetches it: Tauri's
    # <tt>ChannelDataIpcQueue</tt>, a map from data id to body under one
    # lock (channel.rs:44-46).
    #
    # Every app manages one (app.rs:2260), so a handle's
    # <tt>state(Tokra::Ipc::ChannelDataIpcQueue)</tt> finds it. Channel
    # inserts a large message's body under a fresh id, and
    # <tt>plugin:__TAURI_CHANNEL__|fetch</tt> removes it. Nothing else
    # removes data, so data a page never fetches stays for the life of
    # the app, as in Tauri.
    class ChannelDataIpcQueue
      # An empty queue.
      def initialize
        @data = {} #: Hash[Integer, String]
        @lock = Thread::Mutex.new
      end

      # Stores +body+, a body String (Channel#send), under +id+ and
      # returns +nil+. Tauri's queue is crate-private and Channel reaches
      # into its HashMap; Ruby has no crate privacy, so these two methods
      # are that map's +insert+ and +remove+ (channel.rs:170-176, 329).
      #
      # === Example
      #
      #   queue.insert(0, "[1,2]")
      def insert(id, body)
        @lock.synchronize { @data[id] = body }
        nil
      end

      # Removes and returns the body under +id+, or +nil+ if there is none.
      #
      # === Example
      #
      #   queue.remove(0)  #=> "[1,2]"
      def remove(id)
        @lock.synchronize { @data.delete(id) }
      end
    end

    class Channel
      # The core plugin that hands queued channel data to the page:
      # Tauri's <tt>channel::plugin()</tt>, named
      # <tt>__TAURI_CHANNEL__</tt>, with its one command, +fetch+
      # (channel.rs:318-346). Tokra registers it on every app, as
      # <tt>App::build</tt> does (app.rs:2261).
      class Plugin < Tokra::Plugin
        # The plugin's name, CHANNEL_PLUGIN_NAME.
        def name
          CHANNEL_PLUGIN_NAME
        end

        # Answers +fetch+: the body queued under the id in the
        # <tt>Tauri-Channel-Id</tt> header, as a Response, so bytes reach
        # the page as an ArrayBuffer and JSON as its value. The data
        # leaves the queue. A header that is missing, not visible ASCII,
        # or not a u32 rejects with <tt>missing channel id header</tt>,
        # and an id with no data with <tt>data not found</tt>. Returns
        # +false+ for any other command.
        def extend_api(invoke)
          return false unless invoke.command == "fetch"

          id = data_id(invoke.headers[CHANNEL_ID_HEADER_NAME.downcase])
          queue = invoke.webview.state(ChannelDataIpcQueue) #: ChannelDataIpcQueue
          data = id && queue.remove(id)
          if id.nil?
            invoke.reject("missing channel id header")
          elsif data.nil?
            invoke.reject("data not found")
          else
            invoke.resolve(Response.new(data))
          end
          true
        end

        # The header's value as a u32, read as <tt>to_str</tt> and
        # <tt>u32::from_str</tt> read it: visible ASCII, an optional +,
        # then digits. +nil+ when any step fails (channel.rs:323-327).
        private def data_id(value)
          return nil unless value&.b&.match?(/\A\+?[0-9]+\z/n)

          id = Integer(value.delete_prefix("+"), 10)
          id if id <= 0xFFFF_FFFF
        end
      end
    end
  end
end

# SPDX-SnippetEnd
