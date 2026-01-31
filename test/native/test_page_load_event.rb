# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Native::PageLoadEvent
class TestNativePageLoadEvent < Minitest::Test
  def test_is_defined
    assert defined?(Tokra::Native::PageLoadEvent), "PageLoadEvent should be defined"
  end

  def test_new_accepts_event_and_url
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")

    assert_kind_of Tokra::Native::PageLoadEvent, event
  end

  def test_event_returns_started_or_finished
    started = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")
    finished = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    assert_equal "started", started.event
    assert_equal "finished", finished.event
  end

  def test_url_returns_page_url
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/page")

    assert_equal "https://example.com/page", event.url
  end

  def test_started_predicate_returns_true_when_started
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")

    assert event.started?, "#started? should return true for 'started' event"
  end

  def test_started_predicate_returns_false_when_finished
    event = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    refute event.started?, "#started? should return false for 'finished' event"
  end

  def test_finished_predicate_returns_true_when_finished
    event = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    assert event.finished?, "#finished? should return true for 'finished' event"
  end

  def test_finished_predicate_returns_false_when_started
    event = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")

    refute event.finished?, "#finished? should return false for 'started' event"
  end

  # Mutation testing: ensure predicates are checking the right value
  def test_predicates_are_mutually_exclusive
    started = Tokra::Native::PageLoadEvent.new("started", "https://example.com/")
    finished = Tokra::Native::PageLoadEvent.new("finished", "https://example.com/")

    refute_equal started.started?, started.finished?,
      "started? and finished? should be mutually exclusive for 'started'"
    refute_equal finished.started?, finished.finished?,
      "started? and finished? should be mutually exclusive for 'finished'"
  end
end
