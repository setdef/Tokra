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

  def test_a_foreign_origin_is_rejected_over_post_message
    assert_equal({ "rejected" => "Command ping not allowed by ACL" },
      check_detail(@run, "foreign origin over postMessage"))
  end
end
