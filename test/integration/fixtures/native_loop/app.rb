# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for native_loop_test.rb: the native event loop sharing Ruby's GVL
# with other threads (Plan 020, ADR 012). It drives Tokra::Native directly,
# without an App, so each mode isolates one behavior of the loop. Each mode
# prints a few lines and ends the process itself; a hang is the failure.
#
#   --cpu=N          N CPU-bound threads spin; a ticker wakes the loop every
#                    100 ms. Prints WAKEUPS <count> <max latency ms>, exits 0.
#   --before-run     with --cpu, start the threads before EventLoop#run, so
#                    they already wait for the GVL when the loop starts.
#   --ticker-wait    a ticker sleeps in a loop; prints READY and waits for a
#                    signal.
#   --idle           no other thread, and no event after the first, which
#                    prints READY; waits for a signal (Plan 034).
#   --trap-usr1      a USR1 trap prints TRAPPED USR1 and keeps running.
#   --trap-term-exit=N
#                    a TERM trap prints TRAPPED TERM and exits with N.
#   --gc-drop        three bare windows and three heartbeating webviews (in
#                    windows the app keeps) become unreachable; a background
#                    thread collects them. Prints STILL_BEATING <count of
#                    webviews still beating>.
#   --responses      answers requests from background threads, drops one
#                    from a background thread (DROPPED <what answering it
#                    afterwards said>), and keeps one unanswered; at_exit
#                    answers it once the loop is gone and prints
#                    LATE_RESPONSE <error message>, then what an exit
#                    and a close request say (LATE_REQUEST_EXIT,
#                    LATE_REQUEST_CLOSE).
#
# An ensure around the loop prints ENSURE.
#
#   bundle exec ruby test/integration/fixtures/native_loop/app.rb --cpu=3

require_relative "../../../../lib/tokra"
require "optparse"

options = { cpu: 0 }
OptionParser.new do |parser|
  parser.on("--cpu=N", Integer) { |n| options[:cpu] = n }
  parser.on("--before-run") { options[:before_run] = true }
  parser.on("--ticker-wait") { options[:ticker_wait] = true }
  parser.on("--idle") { options[:idle] = true }
  parser.on("--trap-usr1") { options[:trap_usr1] = true }
  parser.on("--trap-term-exit=N", Integer) { |n| options[:trap_term_exit] = n }
  parser.on("--gc-drop") { options[:gc_drop] = true }
  parser.on("--responses") { options[:responses] = true }
end.parse!(ARGV)

$stdout.sync = true
at_exit { puts "AT_EXIT" }

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def page(script)
  "<!doctype html><meta charset=utf-8><body><script>#{script}</script>"
end

event_loop = Tokra::Native::EventLoop.new
# On macOS, never become the active app, and keep each window with a page
# in sight, and out of the cursor's way, so WebKit does not throttle it, as
# FixtureApp.background and FixtureApp.keep_in_sight do for the other
# fixtures
# (support/fixture_app.rb); tao defines set_activation_policy only there.
BACKGROUND = event_loop.respond_to?(:set_activation_policy)
event_loop.set_activation_policy("Prohibited") if BACKGROUND
main_window = Tokra::Native::Window.new(event_loop)
main_window.set_size(320.0, 240.0)
if BACKGROUND
  main_window.set_always_on_top(true)
  main_window.set_ignore_cursor_events(true)
end
proxy = event_loop.create_proxy

# Spins forever, holding the GVL for every time slice it gets.
def spin = Thread.new { x = 0; loop { x += 1 } }

# Wakes the loop every 100 ms with the time it asked.
def ticker(proxy) = Thread.new { loop { sleep 0.1; proxy.wake_up(now.to_s) } }

# Three webviews that beat over tokra:// every 100 ms, built in a method so
# nothing in Ruby keeps them. Their windows stay: a closed window would
# throttle its page's timers and hide whether the webview itself went.
# Three bare windows go too.
KEPT_WINDOWS = []

def heartbeats(event_loop, proxy)
  3.times do |id|
    window = Tokra::Native::Window.new(event_loop)
    window.set_size(160.0, 120.0)
    if BACKGROUND
      window.set_always_on_top(true)
      window.set_ignore_cursor_events(true)
    end
    KEPT_WINDOWS << window
    Tokra::Native::WebView.new_with_protocol(window, proxy, ["window.BEAT_ID = #{id};"])
  end
  3.times { Tokra::Native::Window.new(event_loop) }
  nil
end

handler = if options[:cpu].positive?
  latencies = []
  started = nil
  start = lambda do
    started = now
    options[:cpu].times { spin }
    ticker(proxy)
  end
  start.call if options[:before_run]
  proxy.wake_up("start") unless options[:before_run]
  lambda do |event|
    next unless event.is_a?(Tokra::Native::WakeUpEvent)
    next start.call if event.payload == "start"

    latencies << ((now - Float(event.payload)) * 1000).round
    if now - started > 4
      puts "WAKEUPS #{latencies.size} #{latencies.max}"
      exit 0
    end
  end
elsif options[:ticker_wait]
  Thread.new { loop { sleep 0.1 } }
  puts "READY"
  -> (_event) {}
elsif options[:idle]
  trap("USR1") { puts "TRAPPED USR1" } if options[:trap_usr1]
  if options[:trap_term_exit]
    trap("TERM") do
      puts "TRAPPED TERM"
      exit options[:trap_term_exit]
    end
  end
  proxy.wake_up("ready")
  lambda do |event|
    puts "READY" if event.is_a?(Tokra::Native::WakeUpEvent) && event.payload == "ready"
  end
elsif options[:gc_drop]
  heartbeats(event_loop, proxy)
  beats = {}
  collected_at = nil
  lambda do |event|
    case event
    when Tokra::Native::HttpRequestEvent
      if event.uri.include?("/beat")
        id = Integer(event.uri[/id=(\d+)/, 1])
        first = beats.empty?
        beats[id] = now
        proxy.respond(event.request_id, 204, [], "")
        if first
          Thread.new do
            sleep 1
            3.times { GC.start }
            proxy.wake_up("collected")
          end
        end
      else
        html = page("setInterval(() => fetch('/beat?id=' + window.BEAT_ID), 100);")
        proxy.respond(event.request_id, 200, [["Content-Type", "text/html"]], html)
      end
    when Tokra::Native::WakeUpEvent
      if event.payload == "collected"
        collected_at = now
        Thread.new { sleep 2; proxy.wake_up("check") }
      else
        puts "STILL_BEATING #{beats.count { |_id, at| at > collected_at + 1 }}"
        exit 0
      end
    end
  end
elsif options[:responses]
  held = nil
  at_exit do
    late = Thread.new do
      proxy.respond(held, 200, [], "late")
      "answered"
    rescue RuntimeError => e
      e.message
    end.value
    puts "LATE_RESPONSE #{late}"
    %i[request_exit request_close].each do |request|
      args = (request == :request_exit) ? [0] : []
      outcome = begin
        proxy.public_send(request, *args)
        "sent"
      rescue RuntimeError => e
        e.message
      end
      puts "LATE_#{request.upcase} #{outcome}"
    end
  end
  Tokra::Native::WebView.new_with_protocol(main_window, proxy, [])
  script = <<~JS
    (async () => {
      const answered = await (await fetch('/answer')).text();
      fetch('/drop');
      fetch('/hold');
      await fetch('/report?answered=' + answered);
    })();
  JS
  lambda do |event|
    next unless event.is_a?(Tokra::Native::HttpRequestEvent)

    id = event.request_id
    case event.uri
    when %r{/answer} then Thread.new { proxy.respond(id, 200, [], "from a thread") }
    when %r{/drop}
      Thread.new do
        proxy.drop_response(id)
        after = begin
          proxy.respond(id, 200, [], "")
          "answered"
        rescue RuntimeError => e
          e.message
        end
        puts "DROPPED #{after}"
      end
    when %r{/hold} then held = id
    when %r{/report}
      puts "REPORT #{event.uri[/\?(.*)/, 1]}"
      Thread.new { sleep 0.5; proxy.wake_up("done") }
    else
      Thread.new { proxy.respond(id, 200, [["Content-Type", "text/html"]], page(script)) }
    end
  end
end

handler ||= -> (_event) {}
begin
  event_loop.run(lambda do |event|
    exit 0 if event.is_a?(Tokra::Native::WakeUpEvent) && event.payload == "done"
    handler.call(event)
  end)
ensure
  puts "ENSURE"
end
