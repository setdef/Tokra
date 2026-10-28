# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Ipc::Channel and Tokra::Ipc::JavaScriptChannelId, against
# the scripts Tauri's ipc/channel.rs evaluates.
class TestChannel < Minitest::Test
  Channel = Tokra::Ipc::Channel
  JavaScriptChannelId = Tokra::Ipc::JavaScriptChannelId

  # A real webview on a real handle built on this thread, so evaluations
  # run at once; the native webview records them.
  private def webview
    @webview ||= begin
      handle = Tokra::Builder.default.build(native: StubNative).handle
      window = Tokra::Window.new(label: "main", native: Object.new, app_handle: handle)
      Tokra::Webview.new(label: "main", native: StubNative::WebView.new, window:, app_handle: handle)
    end
  end

  private def evals
    webview.native.evals
  end

  private def invoke(payload)
    Tokra::Ipc::Invoke.new(command: "register", payload:, responder: nil, webview:)
  end

  def test_a_channel_id_is_the_prefix_and_a_u32
    assert_equal 42, JavaScriptChannelId.from_str("__CHANNEL__:42").callback
    assert_equal 7, JavaScriptChannelId.from_str("__CHANNEL__:+7").callback
    assert_equal 4_294_967_295, JavaScriptChannelId.from_str("__CHANNEL__:4294967295").callback
  end

  # channel.rs:121-130: a missing prefix and a bad id have messages of
  # their own; the id is u32::from_str's grammar.
  def test_a_bad_channel_string_raises_tauris_message
    assert_equal "invalid channel string", assert_raises(ArgumentError) { JavaScriptChannelId.from_str("42") }.message
    ["__CHANNEL__:", "__CHANNEL__:-1", "__CHANNEL__:4294967296", "__CHANNEL__:1.0", "__CHANNEL__: 1", "__CHANNEL__:+"].each do |text|
      assert_equal "invalid channel ID", assert_raises(ArgumentError) { JavaScriptChannelId.from_str(text) }.message, text
    end
  end

  # channel_on, channel.rs:134-185: each message carries the JSON and its
  # index, counting from zero.
  def test_a_channel_on_a_webview_sends_each_message_with_its_index
    channel = JavaScriptChannelId.from_str("__CHANNEL__:9").channel_on(webview)

    assert_nil channel.send({ "shortcut" => "F19", "id" => 1 })
    channel.send("two")

    assert_equal [
      'window.__TAURI_INTERNALS__.runCallback(9, { message: {"shortcut":"F19","id":1}, index: 0 })',
      'window.__TAURI_INTERNALS__.runCallback(9, { message: "two", index: 1 })',
    ], evals
    assert_equal 9, channel.id
  end

  # The data id in a fetch script.
  private def data_id(script)
    Integer(script[/'Tauri-Channel-Id': '(\d+)'/, 1])
  end

  private def queue
    webview.state(Tokra::Ipc::ChannelDataIpcQueue)
  end

  # Tauri's fetch script, verbatim (channel.rs:178-180).
  private def fetch_script(callback_id, data_id, index)
    "window.__TAURI_INTERNALS__.invoke('plugin:__TAURI_CHANNEL__|fetch', null, " \
      "{ headers: { 'Tauri-Channel-Id': '#{data_id}' } }).then((response) => " \
      "window.__TAURI_INTERNALS__.runCallback(#{callback_id}, { message: response, index: #{index} }))" \
      ".catch(console.error)"
  end

  # MAX_JSON_DIRECT_EXECUTE_THRESHOLD, channel.rs:37 and 155-162: JSON
  # shorter than 8192 bytes is evaluated, and 8192 bytes or more is queued
  # and fetched. A string of N characters is N + 2 bytes of JSON.
  def test_json_of_8192_bytes_or_more_goes_through_the_fetch_command
    channel = JavaScriptChannelId.from_str("__CHANNEL__:3").channel_on(webview)
    channel.send("x" * 8189)
    channel.send("x" * 8190)

    assert_equal %(window.__TAURI_INTERNALS__.runCallback(3, { message: "#{'x' * 8189}", index: 0 })), evals[0]
    id = data_id(evals[1])
    assert_equal fetch_script(3, id, 1), evals[1]
    assert_equal %("#{'x' * 8190}"), queue.remove(id)
    assert_nil queue.remove(id), "fetching takes the data out of the queue"
  end

  # The threshold counts bytes, as Rust's String::len does.
  def test_the_json_threshold_counts_bytes
    channel = JavaScriptChannelId.from_str("__CHANNEL__:3").channel_on(webview)
    channel.send("é" * 4095)

    assert_equal fetch_script(3, data_id(evals[0]), 0), evals[0]
  end

  # MAX_RAW_DIRECT_EXECUTE_THRESHOLD, channel.rs:39 and 163-181: bytes
  # shorter than 1024 become an ArrayBuffer inline, 1024 or more are queued
  # as bytes and fetched.
  def test_raw_bytes_of_1024_or_more_go_through_the_fetch_command
    channel = JavaScriptChannelId.from_str("__CHANNEL__:4").channel_on(webview)
    small = ("\x00\xFF".b * 512).byteslice(0, 1023)
    large = "\x01".b * 1024
    channel.send(Tokra::Ipc::Response.new(small))
    channel.send(Tokra::Ipc::Response.new(large))

    assert_equal "window.__TAURI_INTERNALS__.runCallback(4, { message: new Uint8Array(#{JSON.generate(small.bytes)}).buffer, index: 0 })",
      evals[0]
    id = data_id(evals[1])
    assert_equal fetch_script(4, id, 1), evals[1]
    stored = queue.remove(id)
    assert_equal large, stored
    assert_equal Encoding::BINARY, stored.encoding
  end

  # A Response of text is JSON text, sent verbatim (ipc/mod.rs:106-116).
  def test_a_response_of_text_is_sent_as_json_text
    channel = JavaScriptChannelId.from_str("__CHANNEL__:4").channel_on(webview)
    channel.send(Tokra::Ipc::Response.new('{"a":1}'))

    assert_equal ['window.__TAURI_INTERNALS__.runCallback(4, { message: {"a":1}, index: 0 })'], evals
  end

  # CHANNEL_DATA_COUNTER, channel.rs:42 and 169: one process-wide u32
  # counter for every channel, wrapping as AtomicU32::fetch_add does.
  def test_data_ids_come_from_one_counter_that_wraps
    first = JavaScriptChannelId.from_str("__CHANNEL__:1").channel_on(webview)
    second = JavaScriptChannelId.from_str("__CHANNEL__:2").channel_on(webview)
    first.send("x" * 9000)
    second.send("x" * 9000)
    assert_equal data_id(evals[0]) + 1, data_id(evals[1])

    saved = Channel.instance_variable_get(:@data_counter)
    begin
      Channel.instance_variable_set(:@data_counter, 0xFFFF_FFFF)
      first.send("x" * 9000)
      first.send("x" * 9000)
    ensure
      Channel.instance_variable_set(:@data_counter, saved)
    end
    assert_equal [0xFFFF_FFFF, 0], [data_id(evals[2]), data_id(evals[3])]
  end

  # The end message follows the fetch script, with the next index; the
  # page holds it until the fetched message lands (core.ts Channel). A
  # dropped channel leaves its unfetched data queued, as Tauri's does.
  def test_a_fetched_message_keeps_its_index_before_the_end
    channel = JavaScriptChannelId.from_str("__CHANNEL__:6").channel_on(webview)
    channel.send("x" * 9000)
    channel.drop
    channel.send("x" * 9000)

    id = data_id(evals[0])
    assert_equal [fetch_script(6, id, 0), "window.__TAURI_INTERNALS__.runCallback(6, { end: true, index: 1 })"], evals
    assert_equal %("#{'x' * 9000}"), queue.remove(id)
  end

  # Channel::from_callback_fn (channel.rs:244-284): the same three paths,
  # with the message itself as the callback's argument and no index.
  def test_a_channel_for_an_invoke_result_sends_the_bare_message
    channel = Channel.from_callback_fn(webview, 8)
    channel.send({ "a" => 1 })
    channel.send(Tokra::Ipc::Response.new("\x01\x02".b))
    channel.send("x" * 9000)
    channel.send(Tokra::Ipc::Response.new("\x03".b * 1024))

    assert_equal 'window.__TAURI_INTERNALS__.runCallback(8, {"a":1})', evals[0]
    assert_equal "window.__TAURI_INTERNALS__.runCallback(8, new Uint8Array([1,2]).buffer)", evals[1]
    [2, 3].each do |n|
      assert_equal "window.__TAURI_INTERNALS__.invoke('plugin:__TAURI_CHANNEL__|fetch', null, " \
        "{ headers: { 'Tauri-Channel-Id': '#{data_id(evals[n])}' } }).then((response) => " \
        "window.__TAURI_INTERNALS__.runCallback(8, response)).catch(console.error)", evals[n]
    end
    assert_equal "\x03".b * 1024, queue.remove(data_id(evals[3]))
    assert_equal 8, channel.id
  end

  def test_non_finite_floats_serialize_as_null
    channel = JavaScriptChannelId.from_str("__CHANNEL__:3").channel_on(webview)
    channel.send([Float::NAN, 1.5])

    assert_equal ["window.__TAURI_INTERNALS__.runCallback(3, { message: [null,1.5], index: 0 })"], evals
  end

  # The on_drop of channel_on (channel.rs:186-193) tells the page the
  # channel ended, at the index after the last message, once; nothing is
  # sent after it, as Rust cannot send through a dropped channel
  # (channel.rs:80-86).
  def test_dropping_a_channel_ends_it_once
    channel = JavaScriptChannelId.from_str("__CHANNEL__:5").channel_on(webview)
    channel.send(1)
    channel.drop
    channel.drop
    channel.send(2)

    assert_equal [
      "window.__TAURI_INTERNALS__.runCallback(5, { message: 1, index: 0 })",
      "window.__TAURI_INTERNALS__.runCallback(5, { end: true, index: 1 })",
    ], evals
  end

  # on_drop ignores a webview that can no longer evaluate, as Tauri's
  # let _ = does (channel.rs:186-193).
  def test_dropping_a_channel_after_the_loop_ends_raises_nothing
    channel = JavaScriptChannelId.from_str("__CHANNEL__:5").channel_on(webview)
    webview.app_handle.runtime_context.close

    assert_raises(Tokra::Error::Runtime) { Thread.new { Thread.current.report_on_exception = false; channel.send(1) }.join }
    assert_nil Thread.new { channel.drop }.value
  end

  def test_a_channel_serializes_as_its_payload_string
    channel = JavaScriptChannelId.from_str("__CHANNEL__:5").channel_on(webview)

    assert_equal '"__CHANNEL__:5"', JSON.generate(channel)
    assert_equal '{"handler":"__CHANNEL__:5"}', JSON.generate({ "handler" => channel })
  end

  # Channel::new: a Ruby handler, and ids from a process-wide counter.
  def test_a_new_channel_calls_its_block_with_the_body
    bodies = []
    first = Channel.new { |body| bodies << body }
    second = Channel.new { |_body| nil }
    first.send({ "a" => [1] })
    first.send(Tokra::Ipc::Response.new("\xFF".b))
    first.drop
    first.send("after the drop")

    assert_equal ['{"a":[1]}', "\xFF".b], bodies
    assert_equal Encoding::BINARY, bodies.last.encoding
    assert_equal first.id + 1, second.id
  end

  def test_a_new_channel_needs_a_block
    assert_raises(ArgumentError) { Channel.new }
  end

  # The CommandArg impl, channel.rs:300-316.
  def test_from_command_reads_the_channel_for_the_calling_webview
    channel = Channel.from_command(invoke({ "handler" => "__CHANNEL__:11" }), "handler")
    channel.send(true)

    assert_equal 11, channel.id
    assert_equal ["window.__TAURI_INTERNALS__.runCallback(11, { message: true, index: 0 })"], evals
  end

  # A value that is not a string is serde's InvalidArgs; a string that is
  # not a channel is a bare InvokeError (channel.rs:305-313).
  def test_from_command_rejects_what_tauri_rejects
    assert_equal "invalid args `handler` for command `register`: command register missing required key handler",
      assert_raises(Tokra::Error::InvalidArgs) { Channel.from_command(invoke({}), "handler") }.message
    assert_equal "invalid args `handler` for command `register`: invalid type: integer `1`, expected a string",
      assert_raises(Tokra::Error::InvalidArgs) { Channel.from_command(invoke({ "handler" => 1 }), "handler") }.message
    assert_equal "invalid channel value `__CHANNEL__:x`, expected a string in the `__CHANNEL__:ID` format",
      assert_raises(Tokra::Ipc::InvokeError) { Channel.from_command(invoke({ "handler" => "__CHANNEL__:x" }), "handler") }.message
  end

  def test_the_channel_plugin_names_are_tauris
    assert_equal "__CHANNEL__:", Channel::IPC_PAYLOAD_PREFIX
    assert_equal "__TAURI_CHANNEL__", Channel::CHANNEL_PLUGIN_NAME
    assert_equal "plugin:__TAURI_CHANNEL__|fetch", Channel::FETCH_CHANNEL_DATA_COMMAND
  end
end
