# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Native::Icon, tao's window icon, against the real extension (plan 041,
# decision 4). It needs no event loop and builds on any thread, as Tauri
# converts an image before it sends it (tauri-runtime-wry lib.rs:490-499).
class TestNativeIcon < Minitest::Test
  def test_an_image_that_fills_its_size_is_an_icon
    assert_kind_of Tokra::Native::Icon, Tokra::Native::Icon.from_rgba("\xFF".b * 16, 2, 2)
  end

  def test_another_thread_can_build_one
    icon = Thread.new { Tokra::Native::Icon.from_rgba("\xFF".b * 4, 1, 1) }.value

    assert_kind_of Tokra::Native::Icon, icon
  end

  # tao's BadIcon texts (tao 0.34.5 src/icon.rs:42-79), on every platform.
  def test_a_bad_image_raises_taos_reason
    {
      ["\x00".b * 16, 0, 4] => "The specified dimensions (0x4) must be greater than zero.",
      ["\x00".b * 5, 1, 1] => "The length of the `rgba` argument (5) isn't divisible by 4, making it impossible " \
        "to interpret as 32bpp RGBA pixels.",
      ["\x00".b * 12, 2, 2] => "The specified dimensions (2x2) don't match the number of pixels supplied by the " \
        "`rgba` argument (3). For those dimensions, the expected pixel count is 4.",
    }.each do |(rgba, width, height), message|
      error = assert_raises(RuntimeError) { Tokra::Native::Icon.from_rgba(rgba, width, height) }
      assert_equal message, error.message
    end
  end
end
