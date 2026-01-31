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

  def test_on_webview_event_receives_enter_event_with_pathnames
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    StubNative.inject_event(Tokra::Native::DragDropEvent.new(
      "enter", ["/tmp/file1.txt", "/tmp/file2.txt"], 100, 200
    ))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::WebviewEvent::DragDrop, event
    assert_instance_of Tokra::DragDropEvent::Enter, event.event

    # Verify paths are converted to Pathname (mutation-resistant)
    assert_equal 2, event.event.paths.size
    assert_instance_of Pathname, event.event.paths.first
    assert_equal Pathname.new("/tmp/file1.txt"), event.event.paths.first
    assert_equal Pathname.new("/tmp/file2.txt"), event.event.paths.last

    # Verify position (mutation-resistant)
    assert_equal 100, event.event.position.x
    assert_equal 200, event.event.position.y
  end

  def test_on_webview_event_receives_drop_event_with_pathnames
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    StubNative.inject_event(Tokra::Native::DragDropEvent.new(
      "drop", ["/Users/kerrick/Desktop/photo.jpg"], 50, 75
    ))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::DragDropEvent::Drop, event.event
    assert_equal Pathname.new("/Users/kerrick/Desktop/photo.jpg"), event.event.paths.first
    assert_equal 50, event.event.position.x
    assert_equal 75, event.event.position.y
  end

  def test_on_webview_event_receives_over_event
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    StubNative.inject_event(Tokra::Native::DragDropEvent.new("over", [], 123, 456))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::DragDropEvent::Over, event.event
    assert_equal 123, event.event.position.x
    assert_equal 456, event.event.position.y
  end

  def test_on_webview_event_receives_leave_event
    Thread.current[:received_event] = nil
    hook = Ractor.shareable_proc do |_webview, event|
      Thread.current[:received_event] = event
    end

    StubNative.inject_event(Tokra::Native::DragDropEvent.new("leave", [], 0, 0))

    Tokra::Builder.default
      .on_webview_event(&hook)
      .run(native: StubNative)

    event = Thread.current[:received_event]
    assert_instance_of Tokra::DragDropEvent::Leave, event.event
  end
end
