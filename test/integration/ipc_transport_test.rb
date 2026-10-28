# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The real @tauri-apps/api invoke, loaded with with_global_tauri, rides the
# ipc:// custom protocol (ADR 010) and never falls back to postMessage. A
# request with the wrong invoke key is left unanswered, as in Tauri.
class IpcTransportTest < RealApp::TestCase
  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("ipc_transport") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_invoke_resolves_with_the_handler_value_over_ipc_protocol
    detail = check_detail(@run, "invoke resolves")
    assert_equal "PINGPONG", detail["reply"]
    assert_equal({ "url" => "ipc://localhost/ping", "status" => 200, "tauriResponse" => "ok" }, detail["fetch"])
  end

  def test_an_unknown_command_rejects_with_tauris_message_over_ipc_protocol
    detail = check_detail(@run, "unknown command rejects")
    assert_equal "Command no_such_command not found", detail["rejected"]
    assert_equal "error", detail.dig("fetch", "tauriResponse")
  end

  # Tauri logs a mismatched invoke key and drops the request unanswered
  # (webview/mod.rs:1728-1744); the page's fetch neither resolves nor
  # rejects, so the client never falls back to postMessage either.
  def test_a_mismatched_invoke_key_is_logged_and_never_answered
    detail = check_detail(@run, "mismatched key is never answered")
    assert_nil detail["settled"], "the ipc:// fetch should stay pending"
    assert_equal "PINGPONG", detail["reply"]
    assert_match(/__TAURI_INVOKE_KEY__ expected \S+ but received not-the-key/, @run.stderr)
  end

  # Tauri parses the body with serde_json before routing
  # (ipc/protocol.rs:287-291, 525-532), so a lone surrogate escape is
  # rejected with serde_json's message instead of reaching the handler;
  # a postMessage failure is console.error'd in the page (protocol.rs:422-430,
  # Plan 032).
  def test_a_body_serde_json_rejects_never_reaches_a_command
    detail = check_detail(@run, "a body serde_json rejects never reaches a command")
    assert_equal "lone leading surrogate in hex escape at line 1 column 18", detail["rejected"]
    assert_equal ["JSON error: lone leading surrogate in hex escape at line 1 column 65"], detail["consoleErrors"]
    refute_includes @run.stderr, "received post-message-probe"
  end

  # A Uint8Array invoke reaches the command as raw bytes and a
  # Response.new(bytes) reply reaches the page as an ArrayBuffer, over
  # ipc:// (ipc/protocol.rs:117-120, 525-526; Plan 033).
  def test_raw_bytes_round_trip_as_an_array_buffer
    detail = check_detail(@run, "raw bytes round trip")
    assert_equal "[object ArrayBuffer]", detail["type"]
    assert_equal 1024 * 1024, detail["size"]
    assert_equal 0, detail["mismatches"]
  end

  # The command sees options.headers, lowercased, and every request
  # header; a plain Array payload is octet-stream text, as Tauri's client
  # sends it.
  def test_raw_request_carries_the_page_headers
    detail = check_detail(@run, "raw request headers")
    assert_equal({ "raw" => true, "body" => [1, 2, 255], "probe" => "café", "contentType" => "application/octet-stream" },
      detail["typed"])
    assert_equal({ "raw" => true, "body" => "1,2,255".bytes, "probe" => nil, "contentType" => "application/octet-stream" },
      detail["array"])
  end

  # After ipc:// fails, the same invoke over postMessage reaches the
  # command as a JSON number array with the same non-ASCII header, and a
  # raw reply is a number array (ipc/protocol.rs:297, 390-402).
  def test_the_post_message_fallback_agrees_with_ipc_protocol
    detail = check_detail(@run, "postMessage fallback")
    assert_equal({ "raw" => false, "body" => [1, 2, 255], "probe" => "café", "contentType" => nil }, detail["described"])
    assert_equal [3, 2, 1], detail["reversed"]
  end

  # A command's Channel messages reach the page's Channel in order: large
  # JSON and a megabyte of bytes through two fetches of
  # plugin:__TAURI_CHANNEL__|fetch over ipc://, small JSON and a few bytes
  # evaluated, bytes as ArrayBuffers (channel.rs:153-182, 318-337; Plan 037).
  def test_channel_messages_arrive_in_order_with_their_bytes
    detail = check_detail(@run, "channel stream")
    assert_equal 4, detail["count"], detail.inspect
    assert_equal ["[object Object]", "[object Object]", "[object ArrayBuffer]", "[object ArrayBuffer]"], detail["types"]
    assert_equal 9000, detail["textLength"]
    assert_equal({ "small" => true }, detail["small"])
    assert_equal [1, 2, 255], detail["fewBytes"]
    assert_equal 1024 * 1024, detail["size"]
    assert_equal 0, detail["mismatches"]
    assert_equal 2, detail["fetches"]
  end

  # After ipc:// fails, the fetch command rides postMessage too, and its
  # bytes come back as a number array (ipc/protocol.rs:337-339, 390-402).
  def test_channel_messages_survive_the_post_message_fallback
    detail = check_detail(@run, "postMessage fallback")["channel"]
    assert_equal 4, detail["count"], detail.inspect
    assert_equal "[object Array]", detail["types"][3]
    assert_equal [2048, 0], [detail["size"], detail["mismatches"]]
  end

  def test_the_client_never_falls_back_to_post_message
    detail = check_detail(@run, "transport")
    assert_empty detail["fallbackWarnings"]
    assert_equal 2, detail["ipcFetches"], "both invokes should be ipc:// fetches"
  end
end
