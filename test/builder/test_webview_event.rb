# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Builder webview event handling (on_webview_event).
class TestBuilderWebviewEvent < Minitest::Test
  def test_on_webview_event_accepts_multiple_listeners
    hook = Ractor.shareable_proc { |_w, _e| :handled }
    builder = Tokra::Builder.default
      .on_webview_event(&hook)
      .on_webview_event(&hook)

    assert_instance_of Tokra::Builder, builder
  end

  # Drops on Tokra's webview are its window's (plan 047, decision 12);
  # test_window_events.rb covers them.
end
