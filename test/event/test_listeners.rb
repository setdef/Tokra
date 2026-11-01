# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# The listener registry, ported from Tauri's event/listener.rs: ids, the
# handlers by event name, targets and filters, once, and the pending queue
# that holds what a handler asks for while an emit holds the registry.
class TestEventListeners < Minitest::Test
  T = Tokra::EventTarget

  def setup
    @listeners = Tokra::Event::Listeners.new
  end

  def test_tauris_fixed_names
    assert_equal "__internal_unstable_listeners_function_id__", @listeners.function_name
    assert_equal "__internal_unstable_listeners_object_id__", @listeners.listeners_object_name
  end

  def test_ids_count_up_from_zero
    assert_equal 0, @listeners.next_event_id
    assert_equal 1, @listeners.listen("a", T.any) { nil }
    assert_equal 2, @listeners.next_event_id
  end

  def test_ids_wrap_as_a_u32
    listeners = Tokra::Event::Listeners.new(next_event_id: 0xFFFF_FFFF)

    assert_equal 0xFFFF_FFFF, listeners.next_event_id
    assert_equal 0, listeners.next_event_id
  end

  def test_emit_calls_each_handler_of_the_event_with_its_id_and_payload
    heard = []
    first = @listeners.listen("a", T.any) { |event| heard << [:first, event] }
    second = @listeners.listen("a", T.app) { |event| heard << [:second, event] }
    @listeners.listen("b", T.any) { |event| heard << [:other, event] }

    @listeners.emit(args("a", "1"))

    assert_equal [[:first, Tokra::Event.new(id: first, payload: "1")], [:second, Tokra::Event.new(id: second, payload: "1")]],
      heard
  end

  def test_a_filter_skips_targets_it_refuses_but_never_any
    heard = []
    @listeners.listen("a", T.any) { heard << :any }
    @listeners.listen("a", T.app) { heard << :app }
    @listeners.listen("a", T.window("main")) { heard << :window }

    @listeners.emit_filter(args("a"), -> (target) { target == T.window("main") })

    assert_equal %i[any window], heard
  end

  def test_unlisten_removes_the_handler
    heard = []
    id = @listeners.listen("a", T.any) { heard << :a }
    @listeners.unlisten(id)

    @listeners.emit(args("a"))

    assert_empty heard
  end

  def test_once_hears_one_event
    heard = []
    @listeners.once("a", T.any) { |event| heard << event.payload }

    @listeners.emit(args("a", "1"))
    @listeners.emit(args("a", "2"))

    assert_equal ["1"], heard
  end

  # A handler that listens, unlistens, or emits while an emit holds the
  # registry is queued, and the queue is flushed once the handlers ran
  # (listener.rs:115-139, 205-232).
  def test_what_a_handler_asks_for_waits_until_the_emit_finishes
    heard = []
    @listeners.listen("a", T.any) do
      heard << :a
      @listeners.listen("a", T.any) { heard << :late }
      @listeners.emit(args("b"))
      heard << :after_nested_emit
    end
    @listeners.listen("b", T.any) { heard << :b }

    @listeners.emit(args("a"))
    assert_equal %i[a after_nested_emit b], heard, "the nested emit runs after the outer handlers"

    heard.clear
    @listeners.emit(args("a"))
    assert_includes heard, :late, "the queued listen took effect"
  end

  # Another thread finds the registry held while a handler runs, so its
  # listen, unlisten, and emit wait in the queue, and the emit holding
  # the registry runs them in order when its handlers are done
  # (listener.rs:139-148, 182-191, 193-226).
  def test_another_threads_calls_wait_for_the_emit_holding_the_registry
    entered = Thread::Queue.new
    release = Thread::Queue.new
    heard = []
    @listeners.listen("a", T.any) do
      entered << true
      release.pop
    end
    doomed = @listeners.listen("c", T.any) { heard << :c }
    emitter = Thread.new { @listeners.emit(args("a")) }
    entered.pop

    @listeners.listen("b", T.any) { heard << :b }
    @listeners.unlisten(doomed)
    @listeners.emit(args("b"))
    @listeners.emit(args("c"))
    assert_empty heard, "nothing ran while the handler held the registry"

    release << true
    emitter.join
    assert_equal [:b], heard, "the queued listen ran before the queued emit, and the unlisten before c's"
  end

  def test_an_unlisten_inside_a_handler_waits_for_the_flush
    heard = []
    id = nil
    id = @listeners.listen("a", T.any) do
      heard << :a
      @listeners.unlisten(id)
    end

    @listeners.emit(args("a"))
    @listeners.emit(args("a"))

    assert_equal [:a], heard
  end

  def test_js_listeners_are_kept_per_webview_and_event
    @listeners.listen_js("a", "main", T.any, 4)
    @listeners.listen_js("a", "main", T.window("main"), 5)
    @listeners.listen_js("a", "other", T.webview("other"), 6)

    assert @listeners.has_js_listener?("a") { |target| target == T.window("main") }
    refute @listeners.has_js_listener?("a") { |target| target == T.window("x") }
    refute @listeners.has_js_listener?("b") { true }

    @listeners.unlisten_js("a", 5)

    refute @listeners.has_js_listener?("a") { |target| target == T.window("main") }
  end

  def test_emit_js_sends_each_webview_the_ids_its_filter_keeps
    main = FakeWebview.new("main")
    other = FakeWebview.new("other")
    quiet = FakeWebview.new("quiet")
    @listeners.listen_js("a", "main", T.any, 1)
    @listeners.listen_js("a", "main", T.app, 2)
    @listeners.listen_js("a", "other", T.webview("x"), 3)

    @listeners.emit_js_filter([main, other, quiet], args("a"), -> (target) { target == T.webview("y") })

    assert_equal [[["a", "null"], [1]]], main.emitted
    assert_equal [[["a", "null"], []]], other.emitted, "a webview with listeners for the event hears it, if with no ids"
    assert_empty quiet.emitted
  end

  # Records emit_js as Webview#emit_js receives it.
  class FakeWebview
    attr_reader :label, :emitted

    def initialize(label)
      @label = label
      @emitted = []
    end

    def emit_js(emit_args, ids)
      @emitted << [[emit_args.event, emit_args.payload], ids]
    end
  end

  private def args(event, payload = "null")
    Tokra::Event::EmitArgs.new(event:, payload:)
  end
end
