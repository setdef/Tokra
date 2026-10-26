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

  # A large message goes through eval as well; Tauri fetches it instead
  # (Plan 025, decision 5), and the page receives the same message.
  def test_a_large_message_is_evaluated_too
    channel = JavaScriptChannelId.from_str("__CHANNEL__:3").channel_on(webview)
    channel.send("x" * 9000)

    assert evals.first.start_with?('window.__TAURI_INTERNALS__.runCallback(3, { message: "xxx')
    assert evals.first.end_with?('", index: 0 })')
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
  def test_a_new_channel_calls_its_block_with_the_json
    bodies = []
    first = Channel.new { |body| bodies << body }
    second = Channel.new { |_body| nil }
    first.send({ "a" => [1] })
    first.drop
    first.send("after the drop")

    assert_equal ['{"a":[1]}'], bodies
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

  def test_from_command_rejects_what_tauri_rejects
    assert_equal "invalid args `handler` for command `register`: command register missing required key handler",
      assert_raises(ArgumentError) { Channel.from_command(invoke({}), "handler") }.message
    assert_equal "invalid args `handler` for command `register`: invalid type: integer `1`, expected a string",
      assert_raises(ArgumentError) { Channel.from_command(invoke({ "handler" => 1 }), "handler") }.message
    assert_equal "invalid channel value `__CHANNEL__:x`, expected a string in the `__CHANNEL__:ID` format",
      assert_raises(ArgumentError) { Channel.from_command(invoke({ "handler" => "__CHANNEL__:x" }), "handler") }.message
  end

  def test_the_channel_plugin_names_are_tauris
    assert_equal "__CHANNEL__:", Channel::IPC_PAYLOAD_PREFIX
    assert_equal "__TAURI_CHANNEL__", Channel::CHANNEL_PLUGIN_NAME
  end
end
