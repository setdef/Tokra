# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Ipc::InvokeBody, Request, and Response: Tauri's raw
# invoke bodies and responses (ipc/mod.rs:52-205), with a binary String
# standing for Rust's Vec<u8> (Plan 033).
class TestRequestResponse < Minitest::Test
  private def stub_webview
    Tokra::Webview.new(label: "test", native: Object.new, window: Object.new, app_handle: Object.new)
  end

  private def invoke(payload, headers: {}, &responder)
    Tokra::Ipc::Invoke.new(command: "cmd", payload:, headers:, responder:, webview: stub_webview)
  end

  def test_only_a_binary_string_is_a_raw_body
    assert Tokra::Ipc::InvokeBody.raw?("\xFF".b)
    assert Tokra::Ipc::InvokeBody.raw?("".b)
    refute Tokra::Ipc::InvokeBody.raw?("text")
    refute Tokra::Ipc::InvokeBody.raw?("text".encode(Encoding::US_ASCII))
    refute Tokra::Ipc::InvokeBody.raw?([1, 2])
    refute Tokra::Ipc::InvokeBody.raw?({})
  end

  # InvokeMessage::payload and headers (ipc/mod.rs:559-581): the body as
  # it came, whatever it is.
  def test_invoke_payload_is_the_body_as_sent
    raw = invoke("\x00".b, headers: { "path" => "a" })
    assert_equal "\x00".b, raw.payload
    assert_same raw.payload, raw.body
    assert_equal({ "path" => "a" }, raw.headers)

    list = invoke([1, 2])
    assert_equal [1, 2], list.payload

    object = invoke({ "a" => 1 })
    assert_equal({ "a" => 1 }, object.body)
    assert_equal({ "a" => 1 }, object.payload)
    assert_equal({}, object.headers, "headers default to none")
  end

  # Request's CommandArg impl reads the invoke's body and headers
  # (ipc/mod.rs:164-171).
  def test_request_from_command_reads_body_and_headers
    request = Tokra::Ipc::Request.from_command(invoke("\x01\x02".b, headers: { "options" => "{}" }))
    assert_equal "\x01\x02".b, request.body
    assert_equal({ "options" => "{}" }, request.headers)
  end

  # IpcResponse for Response hands its body on unserialized
  # (ipc/mod.rs:194-198): bytes as bytes, text as JSON text.
  def test_resolving_a_response_sends_its_body
    calls = []
    invoke({}) { |success, body| calls << [success, body] }.resolve(Tokra::Ipc::Response.new("\xFF".b))
    invoke({}) { |success, body| calls << [success, body] }.resolve(Tokra::Ipc::Response.new("[1]"))
    invoke({}) { |success, body| calls << [success, body] }.resolve("[1]")

    assert_equal [[true, "\xFF".b], [true, "[1]"], [true, '"[1]"']], calls
    assert_equal Encoding::BINARY, calls[0][1].encoding
    refute_equal Encoding::BINARY, calls[1][1].encoding
  end

  # A Rust String is UTF-8 by type (ipc/mod.rs:100-104), so text in any
  # other encoding is sent as its UTF-8.
  def test_response_text_is_utf8
    body = Tokra::Ipc::Response.new('{"t":"é"}'.encode(Encoding::UTF_16LE)).body
    assert_equal Encoding::UTF_8, body.encoding
    assert_equal '{"t":"é"}', body
    assert_equal Encoding::UTF_8, Tokra::Ipc::Response.new("[]".encode(Encoding::US_ASCII)).body.encoding
  end

  # Tauri's reject takes a T: Serialize, which Response is not
  # (ipc/mod.rs:409-418), so Ruby refuses it as Rust's compiler does,
  # before anything is sent.
  def test_rejecting_with_a_response_raises
    calls = []
    subject = invoke({}) { |success, body| calls << [success, body] }
    error = assert_raises(TypeError) { subject.reject(Tokra::Ipc::Response.new("x")) }
    assert_equal "Tokra::Ipc::Response is not an invoke error", error.message
    assert_empty calls
    subject.reject("later")
    assert_equal [[false, '"later"']], calls, "the invoke can still settle"
  end

  # Response::new takes a Vec<u8> or a String (ipc/mod.rs:106-116, 200-205).
  def test_response_takes_only_a_string
    assert_equal "\x01".b, Tokra::Ipc::Response.new("\x01".b).body
    error = assert_raises(TypeError) { Tokra::Ipc::Response.new([1]) }
    assert_equal "no implicit conversion of Array into String", error.message
    assert_raises(Encoding::UndefinedConversionError) { Tokra::Ipc::Response.new("\xAA".dup.force_encoding(Encoding::Windows_1253)) }
    error = assert_raises(ArgumentError) { Tokra::Ipc::Response.new("\xFF".dup.force_encoding(Encoding::UTF_8)) }
    assert_equal "invalid byte sequence in UTF-8", error.message
  end
end
