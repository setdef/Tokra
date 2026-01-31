# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::PageLoadPayload type.
class TestPageLoadPayload < Minitest::Test
  def test_stores_url_and_started
    payload = Tokra::PageLoadPayload.new(url: "tokra://localhost/", started: true)

    assert_equal "tokra://localhost/", payload.url
    assert payload.started?
    refute payload.finished?
  end

  def test_finished_is_inverse_of_started
    payload = Tokra::PageLoadPayload.new(url: "tokra://localhost/about", started: false)

    refute payload.started?
    assert payload.finished?
  end
end
