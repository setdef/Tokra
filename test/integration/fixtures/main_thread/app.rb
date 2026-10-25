# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for main_thread_test.rb: window and webview calls made from
# background Ruby threads reach the native objects on the main thread, as
# Tauri's runtime dispatches them (Plan 020). Each plugin:main-thread|
# command does its work on a fresh Thread and settles the invoke from it,
# so a call the native layer refused on that thread reaches the page as a
# rejection instead of a hang.
#
# Without --wait, the page exits through AppHandle#exit called on a
# background thread. As the loop ends, a thread started in the Exit handler
# waits on Window#title; at_exit prints what it got (WAITER), then what a
# fresh call from another thread gets once the loop is gone (LATE).
#
# To watch it:
#
#   bundle exec ruby test/integration/fixtures/main_thread/app.rb --wait

require_relative "../../support/fixture_app"

options = FixtureApp.options(ARGV)

# What the app hands its at_exit hook.
module MainThreadFixture
  # Seconds at_exit waits for a thread before saying it is still waiting.
  PATIENCE = 10

  class << self
    attr_accessor :window, :waiter
  end

  # The message a background thread's call ended with.
  def self.outcome(thread)
    return "still waiting after #{PATIENCE} s" unless thread.join(PATIENCE)

    thread.value
  end

  # Serves the plugin:main-thread| commands and starts the exit-time waiter.
  class Plugin < Tokra::Plugin
    def name
      "main-thread"
    end

    def on_event(_app, event)
      return unless event.is_a?(Tokra::RunEvent::Exit)

      window = app.get_window("main")
      MainThreadFixture.window = window
      waiter = Thread.new do
        "returned #{window.title.inspect}"
      rescue Tokra::Error => e
        e.message
      end
      # Wait until it is blocked on its reply, so the loop ends with its
      # task still queued.
      Thread.pass until waiter.status == "sleep" || !waiter.alive?
      MainThreadFixture.waiter = waiter
    end

    def extend_api(invoke)
      case invoke.command
      when "eval_from_thread" then on_thread(invoke) { eval_from_thread(invoke) }
      when "title_from_thread" then on_thread(invoke) { title_from_thread(invoke) }
      when "run_on_main_thread" then on_thread(invoke) { run_on_main_thread(invoke) }
      when "wake_after_sleep" then on_thread(invoke) { wake_after_sleep(invoke) }
      when "title_on_main_thread" then invoke.resolve(invoke.webview.window.title)
      when "exit_from_thread" then exit_from_thread(invoke)
      else return false
      end
      true
    end

    # Runs +work+ on a new thread, rejecting the invoke with whatever it
    # raises.
    private def on_thread(invoke, &work)
      Thread.new do
        work.call
      rescue => e
        invoke.reject("#{e.class}: #{e.message}")
      end
    end

    private def eval_from_thread(invoke)
      invoke.webview.eval("window.__fromThread('evaluated')")
      invoke.resolve(true)
    end

    # Reads the title, then sets a new one. tao sets a macOS title
    # asynchronously even on the main thread (util/async.rs:222-228), so
    # the page checks the new title with a later invoke.
    private def title_from_thread(invoke)
      window = invoke.webview.window
      before = window.title
      window.set_title(invoke.payload.fetch("title"))
      invoke.resolve(before)
    end

    private def run_on_main_thread(invoke)
      app.run_on_main_thread { invoke.resolve(Thread.current == Thread.main) }
    end

    # Sleeps while the loop has nothing to do: the thread wakes only if the
    # loop waits without the GVL.
    private def wake_after_sleep(invoke)
      sleep 0.3
      invoke.resolve("woke")
    end

    private def exit_from_thread(invoke)
      code = Integer(invoke.payload.fetch("code"))
      Thread.new { app.exit(code) }
    end
  end
end

at_exit do
  waiter = MainThreadFixture.waiter
  puts "WAITER #{waiter ? MainThreadFixture.outcome(waiter) : 'never started'}"
  window = MainThreadFixture.window
  if window
    late = Thread.new do
      "returned #{window.title.inspect}"
    rescue Tokra::Error => e
      e.message
    end
    puts "LATE #{MainThreadFixture.outcome(late)}"
  end
  puts "AT_EXIT"
end

FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "main thread", plugins: [MainThreadFixture::Plugin])
  .run
