# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The local-origin stopgap (ADR 010 §6) in a real webview: a frame from
# tokra://foreign.test that holds the real invoke key is rejected over both
# transports with Tauri's release-build ACL message, while the app's own page
# is answered.
class OriginAclTest < RealApp::TestCase
  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("origin_acl") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_apps_own_origin_is_answered
    assert_equal "PONG", check_detail(@run, "local origin accepted")["reply"]
  end

  def test_a_foreign_origin_is_rejected_over_the_ipc_protocol
    detail = check_detail(@run, "foreign origin over ipc://")
    assert_equal "tokra://foreign.test", detail["frameOrigin"]
    assert_equal 200, detail["status"]
    assert_equal "error", detail["tauriResponse"]
    assert_equal "Command ping not allowed by ACL", detail["body"]
  end

  # On Linux the check cannot see the frame: wry's WebKitGTK backend reports
  # the webview's top-level URI for every postMessage, not the sending
  # frame's (wry 0.54.1 src/webkitgtk/mod.rs:635-645), so a foreign frame's
  # message carries tokra://localhost and is answered. Tauri parses the same
  # URI (ipc/protocol.rs:302) and decides locality from it
  # (webview/mod.rs:1726), so it has the same gap (ADR 010, section 6). This
  # asserts what Linux does, so a wry change that reports the frame shows up.
  def test_a_foreign_origin_over_post_message_is_rejected_where_wry_reports_the_frame
    expected = if RbConfig::CONFIG["host_os"].include?("linux")
      { "resolved" => "PONG" }
    else
      { "rejected" => "Command ping not allowed by ACL" }
    end

    assert_equal expected, check_detail(@run, "foreign origin over postMessage")
  end
end
