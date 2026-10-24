# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Manager interface requirements.
class TestManager < Minitest::Test
  def test_resources_table_raises_not_implemented_for_bare_includer
    includer = Object.new
    includer.extend(Tokra::Manager)

    error = assert_raises(NotImplementedError) { includer.resources_table }
    assert_match(/resources_table/, error.message)
  end

  def test_app_handle_raises_not_implemented_for_bare_includer
    includer = Object.new
    includer.extend(Tokra::Manager)

    error = assert_raises(NotImplementedError) { includer.app_handle }
    assert_match(/app_handle/, error.message)
  end

  # Native handles hold no app handle; Tokra::Window and Tokra::Webview
  # wrap them and are the Managers, as Window and Webview are in Tauri.
  def test_native_handles_are_not_managers
    refute_includes Tokra::Native::Window.ancestors, Tokra::Manager
    refute_includes Tokra::Native::WebView.ancestors, Tokra::Manager
  end
end
