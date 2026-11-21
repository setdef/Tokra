# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/desktop"

# Tests Desktop (Plan 061): off Windows it never finds a tray or cursor
# missing, and on Windows it names the missing notification area or
# cursor in words a contributor knows, and asks Windows once; off macOS it
# never finds a GUI session missing, and on macOS it names launchd's
# session when that is not Aqua, and asks launchd once.
class TestDesktop < Minitest::Test
  def test_off_windows_nothing_is_missing
    skip "Desktop probes Windows' own desktop here" if Desktop.windows?

    assert_nil Desktop.tray_unavailable_reason
    assert_nil Desktop.cursor_unavailable_reason
  end

  def test_on_windows_each_answer_names_what_is_missing_and_is_asked_once
    skip "Desktop asks Windows only on Windows" unless Desktop.windows?

    tray = Desktop.tray_unavailable_reason
    cursor = Desktop.cursor_unavailable_reason

    assert_includes [nil, "this desktop has no notification area for tray icons (Windows finds no taskbar here)"], tray
    assert(cursor.nil? || cursor.match?(/\Athis desktop has no cursor to read \(GetCursorPos fails with error \d+\)\z/), cursor)
    assert_same tray, Desktop.tray_unavailable_reason
    assert_same cursor, Desktop.cursor_unavailable_reason
  end

  def test_off_macos_no_session_is_missing
    skip "Desktop asks launchd here" if Desktop.macos?

    assert_nil Desktop.session_unavailable_reason
  end

  # A daemon's session, as a build machine's, has no window server.
  def test_a_session_that_is_not_aqua_is_named
    assert_equal 'no macOS GUI session (launchctl managername is "System", not "Aqua")', Desktop.no_session_reason("System")
    assert_equal 'no macOS GUI session (launchctl managername is "", not "Aqua")', Desktop.no_session_reason("")
    assert_nil Desktop.no_session_reason("Aqua")
  end

  def test_on_macos_the_answer_is_launchd_s_and_is_asked_once
    skip "Desktop asks launchd only on macOS" unless Desktop.macos?

    session = IO.popen(["launchctl", "managername"], &:read).strip
    reason = Desktop.session_unavailable_reason

    if session == "Aqua"
      assert_nil reason
    else
      assert_equal Desktop.no_session_reason(session), reason
    end
    assert_same reason, Desktop.session_unavailable_reason
  end
end
