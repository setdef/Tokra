# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Dispatcher adapted from tauri-runtime-wry/src/lib.rs Context,
# send_user_message, getter!, and Message::Task

module Tokra
  # Runs window and webview work on the main thread, from any thread.
  #
  # The operating system ties every window and webview to the thread that
  # runs the event loop. Your app is free to start other Ruby threads, and
  # code on them often has a reason to touch the window: a download that
  # updates the title, a worker that pushes results into the page.
  #
  # Touching a native window from the wrong thread is undefined behavior,
  # and Tokra's native layer refuses it with a ThreadError.
  #
  # This class is the way across. A call made on the main thread runs at
  # once. A call from any other thread is queued, the event loop is woken,
  # and the loop runs the call on the main thread when it gets to it.
  # Commands (set a title, evaluate a script) return without waiting.
  # Queries (read a title) wait for the main thread's answer.
  #
  # You rarely use it directly: Window, Webview, and AppHandle send their
  # native calls through it, and +run_on_main_thread+ on each of them
  # queues your own block.
  #
  # Mirrors tauri-runtime-wry's Context: +send_user_message+ runs the
  # message at once when <tt>current_thread().id() == main_thread_id</tt>
  # and otherwise sends it through the event loop proxy (lib.rs:234-254);
  # +getter+ is the getter! macro, which waits on a channel the main thread
  # answers (lib.rs:196-230); and +handle_task+ runs Message::Task
  # (lib.rs:3212).
  #
  # === Examples
  #
  #   context.run_on_main_thread { window.native.set_title("Done") }
  #
  #   title = context.getter { window.native.title }
  class RuntimeContext
    # The exception a query raised, carried back to the thread that asked.
    Failure = Data.define(:error)

    # Creates a context whose main thread is +main_thread+ until #attach
    # makes it the thread that runs the event loop.
    #
    # [main_thread] the thread that builds the app.
    # [native] the module of native classes the app runs on: Native, or a
    #          test's stand-in for it.
    def initialize(main_thread: Thread.current, native: Native)
      @main_thread = main_thread
      @mutex = Thread::Mutex.new
      @tasks = [] #: Array[[^() -> void, Thread::Queue[Object]?]]
      @proxy = nil
      # What was sent before the loop existed, in order, for #attach.
      @unsent = [] #: Array[^(Native::Proxy) -> void]
      @closed = false
      @window_target = nil
      @native = native
      @menu_natives = nil
      @tray_natives = nil
    end

    # The event loop whose window target answers the app handle's monitor
    # and cursor getters on the main thread, or +nil+ before App#run
    # builds it.
    #
    # Tauri's runtime context holds the loop's window target
    # (tauri-runtime-wry lib.rs:2662-2688); Tokra's native loop lends its
    # target to the getters while it runs (plan 041, decision 1). Read it
    # only on the main thread, inside #getter.
    #
    # === Example
    #
    #   context.getter { context.window_target&.primary_monitor }
    attr_accessor :window_target

    # Whether the calling thread is the main thread.
    #
    # === Example
    #
    #   context.main_thread?  #=> true inside an event callback
    def main_thread?
      Thread.current == @main_thread
    end

    # Connects the context to the event loop through +proxy+, a
    # Native::Proxy, and makes the calling thread, the one about to run the
    # loop, the main thread, as Tauri's runtime records the thread that
    # builds its loop (tauri-runtime-wry lib.rs:2795). Each task queued
    # before the loop existed wakes it now.
    #
    # === Example
    #
    #   context.attach(event_loop.create_proxy)
    def attach(proxy)
      @mutex.synchronize do
        @main_thread = Thread.current
        @proxy = proxy
        @unsent.each { |send| send.call(proxy) }
        @unsent.clear
      end
    end

    # Asks the event loop to exit with +code+ and returns +nil+ without
    # waiting. The loop emits RunEvent::ExitRequested, and exits unless a
    # handler prevents it.
    #
    # The request always travels through the loop, even from the main
    # thread, so the handlers never run inside the caller. Before the loop
    # exists it waits for #attach. Raises Error::Runtime when the event
    # loop has ended.
    #
    # Mirrors the runtime handle's request_exit, which sends
    # Message::RequestExit straight through the proxy (tauri-runtime-wry
    # lib.rs:2623-2629).
    #
    # === Example
    #
    #   context.request_exit(0)
    def request_exit(code)
      send_event { |proxy| proxy.request_exit(code) }
    end

    # Asks the event loop to close the window, as its close button does,
    # and returns +nil+ without waiting. Handlers hear
    # WindowEvent::CloseRequested on a later turn of the loop.
    #
    # Like #request_exit, the request always travels through the loop.
    # Raises Error::Runtime when the event loop has ended.
    #
    # Mirrors the window dispatcher's close, which sends
    # WindowMessage::Close straight through the proxy (tauri-runtime-wry
    # lib.rs:2142-2149).
    #
    # === Example
    #
    #   context.request_close
    def request_close
      send_event(&:request_close)
    end

    # Runs +task+ on the main thread and returns +nil+ without waiting for
    # it.
    #
    # On the main thread the block runs before this method returns, and
    # whatever it raises reaches you. From another thread it runs when the
    # event loop gets to it, in the order it was sent; whatever it raises
    # there is reported and the loop keeps running. Raises Error::Runtime
    # when the event loop has ended.
    #
    # A main-thread callback that waits for another thread which is
    # waiting for the main thread deadlocks, as it does in Tauri.
    #
    # Mirrors the runtime's run_on_main_thread, which sends Message::Task
    # through send_user_message (lib.rs:1523-1525, 2652-2654).
    #
    # === Example
    #
    #   Thread.new do
    #     context.run_on_main_thread { puts Thread.current == Thread.main }
    #   end
    def run_on_main_thread(&task)
      send_user_message(task)
      nil
    end

    # The native menu classes this context's app builds menus with, and
    # the module whose functions put a menu on the app (plan 042,
    # decision 1). Tauri's are its runtime's type parameter.
    def menu_natives # :nodoc:
      @menu_natives ||= Menu::Natives.from(@native)
    end

    # The native tray class this context's app builds trays with (plan
    # 043, decision 1).
    def tray_natives # :nodoc:
      @tray_natives ||= Tray::Natives.from(@native)
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: run_main_thread! adapted from tauri/crates/tauri/src/lib.rs

    # Runs +task+ on the main thread and returns its result, waiting for
    # it when called from another thread, as #getter does.
    #
    # A menu sends every call to its platform objects this way. Raises
    # Error::FailedToReceiveMessage when the event loop ends before it
    # answers, and Error::Runtime when the loop has already ended.
    #
    # Mirrors Tauri's run_main_thread! and run_item_main_thread! macros,
    # which run the closure through run_on_main_thread and wait on a
    # channel, failing with Error::FailedToReceiveMessage when it closes
    # unanswered (lib.rs:1083-1095, menu/mod.rs:25-39).
    #
    # === Example
    #
    #   text = context.run_main_thread { native_item.text }
    def run_main_thread(&task)
      call_and_wait(task, Error::FailedToReceiveMessage.new)
    end

    # SPDX-SnippetEnd

    # Runs +query+ on the main thread and returns its result, waiting for
    # it when called from another thread.
    #
    # A StandardError the query raises is raised here instead. Anything
    # else, such as an Interrupt that a signal raises on the main thread
    # while the query runs, stays on the main thread, where Ruby meant it.
    # Raises
    # Error::Runtime when the event loop has ended, or when it ends before
    # it answers.
    #
    # Mirrors the getter! macro, which sends a message carrying a channel
    # and waits on it, failing with FailedToReceiveMessage when the sender
    # is dropped unanswered (lib.rs:196-230).
    #
    # === Example
    #
    #   title = context.getter { native_window.title }
    def getter(&query)
      call_and_wait(query, Error::Runtime.new(Error::Runtime::FAILED_TO_RECEIVE_MESSAGE))
    end

    # Sends +query+ to the main thread and waits for its answer, raising
    # +unanswered+ if none comes.
    private def call_and_wait(query, unanswered)
      reply = Thread::Queue.new
      task = lambda do
        reply << [query.call]
      rescue => e
        reply << Failure.new(error: e)
      ensure
        # Whatever happened, the answer is in or never coming: like the
        # sender Tauri's handler drops, this ends the caller's wait.
        reply.close
      end
      send_user_message(task, reply)
      answer(reply.pop, unanswered)
    end

    # Runs the oldest queued task on the main thread. The App calls it for
    # each Native::TaskEvent; each queued task woke the loop once.
    #
    # Mirrors handle_user_message's Message::Task arm (lib.rs:3212).
    #
    # === Example
    #
    #   context.handle_task
    def handle_task
      entry = @mutex.synchronize { @tasks.shift }
      entry&.first&.call
      nil
    end

    # Ends dispatch when the event loop has ended.
    #
    # Each getter still waiting fails with FailedToReceiveMessage, as
    # Tauri's do when the loop drops their unanswered channels, and every
    # later call from another thread fails with FailedToSendMessage, as the
    # closed loop proxy fails Tauri's send. Calls on the main thread still
    # run at once.
    #
    # === Example
    #
    #   context.close
    def close
      pending = @mutex.synchronize do
        @closed = true
        @tasks.shift(@tasks.size)
      end
      pending.each { |(_task, reply)| reply&.close }
      nil
    end

    # Runs +task+ at once on the main thread, or queues it and wakes the
    # loop (lib.rs:234-254). +reply+ is the queue a getter waits on.
    private def send_user_message(task, reply = nil)
      if main_thread?
        task.call
        return nil
      end

      @mutex.synchronize do
        raise Error::Runtime, Error::Runtime::FAILED_TO_SEND_MESSAGE if @closed

        wake(@proxy)
        @tasks << [task, reply]
      end
      nil
    end

    # Wakes the event loop for one more task. Before the loop exists the
    # task waits for attach.
    private def wake(proxy)
      send_through(proxy, &:send_task)
    end

    # Sends a request straight through the event loop's proxy, from any
    # thread, the way Tauri's runtime sends the messages that reach its
    # run callback.
    private def send_event(&send)
      @mutex.synchronize do
        raise Error::Runtime, Error::Runtime::FAILED_TO_SEND_MESSAGE if @closed

        send_through(@proxy, &send)
      end
      nil
    end

    # Calls +send+ with +proxy+, or, before the loop exists, keeps it for
    # attach, so everything sent early arrives in order.
    private def send_through(proxy, &send)
      return @unsent << send unless proxy

      send.call(proxy)
    rescue RuntimeError
      raise Error::Runtime, Error::Runtime::FAILED_TO_SEND_MESSAGE
    end

    # The getter's result, from what the main thread put in +reply+: the
    # value in a one-element Array, or a Failure. A closed, empty queue
    # pops +nil+: the answer never came.
    private def answer(reply, unanswered)
      raise unanswered unless reply
      raise reply.error if reply.is_a?(Failure)

      reply.first
    end
  end
end

# SPDX-SnippetEnd
