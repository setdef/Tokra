# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Native::IpcEvent
class TestNativeIpcEvent < Minitest::Test
  def test_is_defined
    assert defined?(Tokra::Native::IpcEvent), "IpcEvent should be defined"
  end

  def test_new_accepts_message
    event = Tokra::Native::IpcEvent.new("hello from JS", "tokra://localhost/")

    assert_kind_of Tokra::Native::IpcEvent, event
  end

  def test_message_returns_stored_string
    event = Tokra::Native::IpcEvent.new("test message", "tokra://localhost/")

    assert_equal "test message", event.message
  end

  def test_message_preserves_unicode
    event = Tokra::Native::IpcEvent.new("こんにちは 🎌", "tokra://localhost/")

    assert_equal "こんにちは 🎌", event.message
  end

  def test_message_preserves_empty_string
    event = Tokra::Native::IpcEvent.new("", "tokra://localhost/")

    assert_equal "", event.message
  end

  def test_url_is_the_posting_frame_url
    event = Tokra::Native::IpcEvent.new(message: "{}", url: "tokra://localhost/page")

    assert_equal "tokra://localhost/page", event.url
    assert_equal "{}", event.message
  end
end
