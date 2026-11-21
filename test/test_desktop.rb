# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/desktop"

# Tests Desktop (Plan 061): off Windows it never finds anything missing,
# and on Windows it names the missing notification area or cursor in
# words a contributor knows, and asks Windows once.
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
end
