# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::UriSchemeContext type.
class TestUriSchemeContext < Minitest::Test
  def test_stores_app_handle_and_label
    handle = Tokra::AppHandle.new({})
    ctx = Tokra::UriSchemeContext.new(app_handle: handle, webview_label: "main")

    assert_same handle, ctx.app_handle
    assert_equal "main", ctx.webview_label
  end
end
