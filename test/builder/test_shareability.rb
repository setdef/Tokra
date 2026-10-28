# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"

# Tests for Tokra::Builder handler shareability enforcement.
# All handlers must be shareable to work across Ractors (Tauri parity).
class TestBuilderShareability < Minitest::Test
  def test_invoke_handler_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.invoke_handler { |_invoke| false }
    end
  end

  def test_register_uri_scheme_protocol_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.register_uri_scheme_protocol("app") { nil }
    end
  end

  def test_register_asynchronous_uri_scheme_protocol_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.register_asynchronous_uri_scheme_protocol("app") { nil }
    end
  end

  def test_setup_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.setup { nil }
    end
  end

  def test_on_page_load_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.on_page_load { nil }
    end
  end

  def test_on_window_event_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.on_window_event { nil }
    end
  end

  def test_on_webview_event_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.on_webview_event { nil }
    end
  end

  def test_menu_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.menu { nil }
    end
  end

  def test_on_menu_event_raises_on_non_shareable_proc
    builder = Tokra::Builder.default
    assert_raises(Tokra::Error) do
      builder.on_menu_event { nil }
    end
  end
end
