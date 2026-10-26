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

  def test_the_client_never_falls_back_to_post_message
    detail = check_detail(@run, "transport")
    assert_empty detail["fallbackWarnings"]
    assert_equal 2, detail["ipcFetches"], "both invokes should be ipc:// fetches"
  end
end
