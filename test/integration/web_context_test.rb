# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# Real webviews built with WebviewWindowBuilder#data_directory (plan 052,
# 052e-3): two that name one directory are built with one wry web
# context and share their local storage, and a third that names another
# is built with its own and does not (webview/mod.rs:968-974;
# tauri-runtime-wry lib.rs:4589-4625). On Linux the second webview of a
# context registers none of the app's protocols, which the first's serve
# (lib.rs:4964-4981), so its page loading at all checks that too. macOS
# ignores the directory: WebKit keeps every webview's data in one store
# there, so the third shares it as well. Each line is caused by a page or
# a command; timeouts are backstops.
class WebContextTest < RealApp::TestCase
  def self.page?
    false
  end

  MACOS = RUBY_PLATFORM.include?("darwin")

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("web_context") }
    assert_finished @run
  end

  def test_exits_cleanly_once_both_readers_have_read
    assert_equal 0, @run.status, @run.describe
    assert_includes @run.lines, "WROTE writer", @run.describe
    assert_includes @run.lines, "CLEARED writer", @run.describe
    assert_equal ["EVENT exit-requested 0", "EVENT exit"], @run.lines.grep(/\AEVENT /), @run.describe
  end

  def test_a_webview_naming_the_writers_directory_reads_its_storage
    assert_includes @run.lines, "READ same shared", @run.describe
  end

  def test_a_webview_naming_another_directory_reads_its_own
    assert_includes @run.lines, "READ other #{MACOS ? 'shared' : 'empty'}", @run.describe
  end
end
