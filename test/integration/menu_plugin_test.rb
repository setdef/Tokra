# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The core menu plugin answers the real menu classes of @tauri-apps/api in
# a real webview, and an item's action hears a click that came through
# muda and the platform's own dispatch (plan 042).
class MenuPluginTest < RealApp::TestCase
  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("menu_plugin") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_the_pages_menu_becomes_the_apps_and_its_actions_hear_clicks
    detail = check_detail(@run, "a menu the page builds")

    assert_equal "js-item", detail["clicked"]
    assert_equal "js-nested", detail["nested"]
    assert_equal [%w[js-item MenuItem], %w[js-check Check], %w[js-nested MenuItem]],
      detail["kinds"].values_at(0, 1, 3)
    assert_equal "Predefined", detail["kinds"][2].last
    assert_equal %w[js-submenu Submenu], detail["found"]
    assert detail["checked"]
    # Only macOS gives an app with no menu of its own Tauri's default one.
    macos = RbConfig::CONFIG["host_os"].include?("darwin")
    macos ? refute_nil(detail["previous"]) : assert_nil(detail["previous"])
  end

  # An image the page made, a NativeIcon (macOS shows it, Windows and
  # Linux do not), and no icon, which Tauri makes NativeIcon::User
  # (plugin.rs:443-449); then setIcon changes each, and an image whose
  # bytes do not make its size rejects with muda's words.
  def test_the_pages_icon_items_show_their_icons_and_set_icon_changes_them
    detail = check_detail(@run, "icon items and a submenu icon the page sets")
    macos = RbConfig::CONFIG["host_os"].include?("darwin")
    assert_equal [true, true, macos, macos], detail["before"]
    assert_equal [false, false, true, macos], detail["after"]
    assert_equal "The specified dimensions (2x2) don't match the number of pixels supplied by the `rgba` argument (1). " \
      "For those dimensions, the expected pixel count is 4.", detail["rejected"]
    assert_equal [%w[js-icon Icon], %w[js-native Icon], %w[js-bare Icon]], detail["kinds"]
    assert_equal "js-icon", detail["action"]
    assert_equal "JS Native", detail["text"]
  end

  def test_a_bad_kind_rejects_in_serdes_words
    detail = check_detail(@run, "a bad kind rejects in serde words")

    assert_equal "invalid args `kind` for command `text`: unknown variant `Bogus`, expected one of " \
      "`Menu`, `MenuItem`, `Predefined`, `Submenu`, `Check`, `Icon`", detail["rejected"]
  end
end
