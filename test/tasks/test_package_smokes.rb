# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# The packaging check's smoke scripts (tasks/package.rake) run in every
# gate, in whatever session runs it, the maintainer's own included, so
# none may change what that session holds: its clipboard, its hotkeys, or
# its notifications.
class TestPackageSmokes < Minitest::Test
  PACKAGE_RAKE = File.expand_path("../../tasks/package.rake", __dir__)

  # The calls that read or change the session's clipboard, take its
  # hotkeys, or post to its notification center. A read is out too: macOS
  # may ask the person whether this process may paste. A schedule is a
  # call, so NotificationData#schedule, an attribute, is not one.
  SESSION_CALLS = /\.((?:write_text|write_image|write_html|read_text|read_image|clear|set_text|set_html|set_image|
    get_text|get_image|register|register_multiple|show|set_application)\b|schedule(?:_raw)?\()/x

  def test_no_smoke_script_touches_the_session
    source = File.read(PACKAGE_RAKE)

    assert_includes source, "Tokra::Plugins::Clipboard::Clipboard.new", "the clipboard smoke still opens arboard's clipboard"
    assert_empty source.scan(SESSION_CALLS).map(&:first), "a smoke script touches the session"
  end
end
