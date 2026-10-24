# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# The core image plugin (plugin:image|new, size, rgba) answers the real
# Image class from @tauri-apps/api in a real webview.
class ImagePluginTest < RealApp::TestCase
  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("image_plugin") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_an_image_round_trips_through_the_resource_table
    detail = check_detail(@run, "image round trip")
    assert_kind_of Integer, detail["rid"]
    assert_equal({ "width" => 2, "height" => 1 }, detail["size"])
    assert_equal [255, 0, 0, 255, 0, 0, 255, 255], detail["rgba"]
  end

  def test_an_unknown_resource_id_rejects
    detail = check_detail(@run, "unknown rid rejects")
    assert_equal Tokra::Error::BadResourceId.new(4_294_967_295).message, detail["rejected"]
  end
end
