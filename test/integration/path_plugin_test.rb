# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The path core plugin answers the real @tauri-apps/api/path module in a
# real webview: its init script's sep and delimiter, its directory
# functions, its path functions, and its rejections (plan 063).
class PathPluginTest < RealApp::TestCase
  IDENTIFIER = "com.tokra.integration.path-plugin"

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("path_plugin") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_separator_and_delimiter_are_the_platforms
    windows = Gem.win_platform?

    assert_equal({ "sep" => windows ? "\\" : "/", "delimiter" => windows ? ";" : ":" },
      check_detail(@run, "separator and delimiter"))
  end

  def test_the_directories_are_the_resolvers
    detail = check_detail(@run, "directories")

    assert_equal Tokra::Native.home_dir, detail["home"]
    assert_equal Tokra::Native.data_local_dir, detail["localData"]
    assert detail["appLocalData"].end_with?(IDENTIFIER), detail["appLocalData"]
    assert_includes detail["appLog"], IDENTIFIER
    refute_empty detail["temp"]
    assert_includes detail["appData"]["rejected"], "data_dir"
    assert_includes detail["resource"]["rejected"], "resource"
  end

  def test_the_path_functions_answer_as_tauris
    detail = check_detail(@run, "path functions")
    sep = Gem.win_platform? ? "\\" : "/"

    assert_equal "a#{sep}c", detail["join"]
    assert_equal "b", detail["basename"]
    assert_equal "json", detail["extname"]
    return if Gem.win_platform?

    assert_equal "/a/c/", detail["normalize"]
    assert_equal "/a", detail["dirname"]
    assert_equal "/a/b", detail["resolve"]
    assert detail["isAbsolute"]
  end

  def test_a_failing_function_rejects_with_tauris_message
    detail = check_detail(@run, "rejections")

    assert_equal({ "rejected" => "path does not have a parent" }, detail["dirname"])
    assert_equal({ "rejected" => "path does not have an extension" }, detail["extname"])
  end
end
