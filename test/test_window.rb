# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/stub_native"

# Tests for Tokra::Window.
class TestWindow < Minitest::Test
  # A real handle, built on this thread, so this thread is the main thread.
  def app_handle
    @app_handle ||= Tokra::Builder.default.build(native: StubNative).handle
  end

  def test_new_with_label_and_native
    native = Object.new
    app_handle = Object.new
    window = Tokra::Window.new(label: "main", native:, app_handle:)

    assert_equal "main", window.label
  end

  def test_resources_table_returns_resource_table
    window = Tokra::Window.new(label: "win", native: Object.new, app_handle: Object.new)
    assert_instance_of Tokra::ResourceTable, window.resources_table
  end

  def test_set_title_delegates_to_native
    native = Minitest::Mock.new
    native.expect :set_title, nil, ["My App"]
    window = Tokra::Window.new(label: "win", native:, app_handle:)

    window.set_title("My App")

    native.verify
  end

  def test_set_size_delegates_to_native
    native = Minitest::Mock.new
    native.expect :set_size, nil, [800.0, 600.0]
    window = Tokra::Window.new(label: "win", native:, app_handle:)

    window.set_size(800.0, 600.0)

    native.verify
  end

  def test_title_returns_the_native_title
    native = Minitest::Mock.new
    native.expect :title, "My App"
    window = Tokra::Window.new(label: "win", native:, app_handle:)

    assert_equal "My App", window.title
    native.verify
  end

  def test_set_title_returns_nil
    window = Tokra::Window.new(label: "win", native: StubNative::Window.new(nil), app_handle:)

    assert_nil window.set_title("My App")
  end

  def test_set_always_on_top_delegates_to_native
    native = Minitest::Mock.new
    native.expect :set_always_on_top, nil, [true]
    window = Tokra::Window.new(label: "win", native:, app_handle:)

    window.set_always_on_top(true)

    native.verify
  end

  def test_set_always_on_top_returns_nil
    window = Tokra::Window.new(label: "win", native: StubNative::Window.new(nil), app_handle:)

    assert_nil window.set_always_on_top(false)
  end

  def test_set_ignore_cursor_events_delegates_to_native
    native = Minitest::Mock.new
    native.expect :set_ignore_cursor_events, nil, [true]
    window = Tokra::Window.new(label: "win", native:, app_handle:)

    window.set_ignore_cursor_events(true)

    native.verify
  end

  def test_set_ignore_cursor_events_returns_nil
    window = Tokra::Window.new(label: "win", native: StubNative::Window.new(nil), app_handle:)

    assert_nil window.set_ignore_cursor_events(false)
  end
end
