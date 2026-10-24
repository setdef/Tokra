# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/real_app"

# A binary asset from a Rack app reaches the real webview byte for byte and
# renders at its own size, whether the body is an array or a file: for a
# to_path body, Rack::Handler::Tokra serves the whole file, byte-exact.
class RackAssetsTest < RealApp::TestCase
  PNG = File.expand_path("../fixtures/2x1.png", __dir__)

  def setup
    super
    @run = self.class.fixture_run { RealApp.launch("rack_assets") }
    assert_finished @run
  end

  def test_exits_cleanly_once_every_check_passed
    assert_equal 0, @run.status, @run.describe
  end

  def test_both_bodies_render_at_the_size_the_file_declares
    image = Tokra::Image.from_path(PNG)
    refute_equal image.width, image.height, "a square fixture would hide swapped dimensions"
    %w[array file].each do |body|
      assert_equal({ "width" => image.width, "height" => image.height }, check_detail(@run, "#{body} body renders"), body)
    end
  end

  def test_both_bodies_arrive_byte_for_byte
    %w[array file].each do |body|
      detail = check_detail(@run, "#{body} body bytes")
      assert_equal "image/png", detail["contentType"], body
      assert_equal File.binread(PNG), detail["base64"].unpack1("m0"), body
    end
  end
end
