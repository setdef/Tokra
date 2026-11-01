# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Listeners adapted from tauri/crates/tauri/src/event/listener.rs

module Tokra
  class Event
    # The app's event registry: Ruby handlers by event name and id, the
    # page's listeners by webview, event, and id, and the queue of what a
    # handler asked for while an emit held the registry.
    #
    # Ruby owns it (ADR 005). One Thread::Mutex guards the handlers, and
    # #try_lock stands in for Rust's, so a listen, unlisten, or emit that
    # finds the registry held, from inside a handler or from another
    # thread, waits in the pending queue until the emit holding it
    # finishes, as Tauri's does. Rust's HashMap gives handlers no order;
    # these run in the order they were added.
    #
    # Mirrors Tauri's <tt>Listeners</tt> (event/listener.rs:58-301).
    class Listeners # :nodoc:
      # A Ruby handler and its target (listener.rs:29-44).
      Handler = Data.define(:target, :callback)

      # A page listener's target and id (listener.rs:46-56).
      JsHandler = Data.define(:target, :id)

      # What to do with a pending action once the registry is free
      # (listener.rs:19-27).
      Unlisten = Data.define(:id) # :nodoc:
      Listen = Data.define(:id, :event, :handler) # :nodoc:
      Emit = Data.define(:emit_args) # :nodoc:

      # Ids are u32s, which fetch_add wraps.
      ID_MASK = 0xFFFF_FFFF

      def initialize(next_event_id: 0)
        @pending = [] #: Array[pending]
        @pending_mutex = Thread::Mutex.new
        @handlers = {} #: Hash[String, Hash[Integer, Handler]]
        @handlers_mutex = Thread::Mutex.new
        @js_event_listeners = {} #: Hash[String, Hash[String, Hash[JsHandler, true]]]
        @js_mutex = Thread::Mutex.new
        @next_event_id = next_event_id
        @id_mutex = Thread::Mutex.new
      end

      # The next id, shared by Ruby and page listeners (listener.rs:87-89).
      def next_event_id
        @id_mutex.synchronize do
          id = @next_event_id
          @next_event_id = (id + 1) & ID_MASK
          id
        end
      end

      # The page's emit function (listener.rs:80, 91-94).
      def function_name
        "__internal_unstable_listeners_function_id__"
      end

      # The page's listeners object (listener.rs:81, 96-99).
      def listeners_object_name
        "__internal_unstable_listeners_object_id__"
      end

      # Adds +handler+ for +event+ and +target+, answering its id
      # (listener.rs:150-160).
      def listen(event, target, &handler)
        id = next_event_id
        listen_with_id(id, event, Handler.new(target:, callback: handler))
        id
      end

      # Adds a handler that hears one event, then unlistens itself
      # (listener.rs:162-180).
      def once(event, target, &handler)
        heard = false
        listen(event, target) do |emitted|
          raise "attempted to call handler more than once" if heard

          heard = true
          handler.call(emitted)
          unlisten(emitted.id)
        end
      end

      # Removes the handler with +id+ (listener.rs:182-191).
      def unlisten(id)
        return insert_pending(Unlisten.new(id:)) unless @handlers_mutex.try_lock

        begin
          @handlers.each_value { |handlers| handlers.delete(id) }
        ensure
          @handlers_mutex.unlock
        end
        nil
      end

      # Calls each handler of the event whose target is Any or passes
      # +filter+, then runs what they queued (listener.rs:193-226).
      def emit_filter(emit_args, filter = nil)
        maybe_pending = false
        if @handlers_mutex.try_lock
          begin
            @handlers[emit_args.event]&.each do |id, handler|
              next unless match_any_or_filter(handler.target, filter)

              maybe_pending = true
              handler.callback.call(Event.new(id:, payload: emit_args.payload))
            end
          ensure
            @handlers_mutex.unlock
          end
        else
          insert_pending(Emit.new(emit_args:))
        end
        flush_pending if maybe_pending
        nil
      end

      # Calls every handler of the event (listener.rs:228-231).
      def emit(emit_args)
        emit_filter(emit_args)
      end

      # Records a page listener of webview +source_webview_label+
      # (listener.rs:233-248).
      def listen_js(event, source_webview_label, target, id)
        @js_mutex.synchronize do
          events = @js_event_listeners[source_webview_label] ||= {}
          (events[event] ||= {})[JsHandler.new(target:, id:)] = true
        end
        nil
      end

      # Forgets the page listener with +id+, in every webview
      # (listener.rs:250-263).
      def unlisten_js(event, id)
        @js_mutex.synchronize do
          @js_event_listeners.each_value do |events|
            handlers = events[event]
            next unless handlers

            handlers.delete_if { |handler, _| handler.id == id }
            events.delete(event) if handlers.empty?
          end
        end
        nil
      end

      # Whether any webview has a page listener for +event+ whose target
      # the block accepts (listener.rs:265-279).
      def has_js_listener?(event, &filter)
        @js_mutex.synchronize do
          @js_event_listeners.each_value.any? do |events|
            handlers = events[event]
            !handlers.nil? && handlers.each_key.any? { |handler| filter.call(handler.target) }
          end
        end
      end

      # Hands the event to each webview with page listeners for it, with
      # the ids whose target is Any or passes +filter+ (listener.rs:281-305).
      def emit_js_filter(webviews, emit_args, filter = nil)
        @js_mutex.synchronize do
          webviews.each do |webview|
            handlers = @js_event_listeners[webview.label]&.[](emit_args.event)
            next unless handlers

            ids = handlers.each_key.select { |handler| match_any_or_filter(handler.target, filter) }.map(&:id)
            webview.emit_js(emit_args, ids)
          end
        end
        nil
      end

      # Hands the event to every page listener (listener.rs:307-313).
      def emit_js(webviews, emit_args)
        emit_js_filter(webviews, emit_args)
      end

      private def listen_with_id(id, event, handler)
        return insert_pending(Listen.new(id:, event:, handler:)) unless @handlers_mutex.try_lock

        begin
          (@handlers[event] ||= {})[id] = handler
        ensure
          @handlers_mutex.unlock
        end
        nil
      end

      private def insert_pending(action)
        @pending_mutex.synchronize { @pending << action }
        nil
      end

      # Runs the queued actions in order (listener.rs:115-139).
      private def flush_pending
        pending = @pending_mutex.synchronize do
          taken = @pending
          @pending = []
          taken
        end
        pending.each do |action|
          case action
          when Unlisten then unlisten(action.id)
          when Listen then listen_with_id(action.id, action.event, action.handler)
          when Emit then emit(action.emit_args)
          end
        end
        nil
      end

      private def match_any_or_filter(target, filter)
        target == EventTarget.any || filter.nil? || filter.call(target)
      end
    end
  end
end

# SPDX-SnippetEnd
