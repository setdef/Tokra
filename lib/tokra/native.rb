# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Native Rust bindings for tao (windowing) and wry (WebView).
  #
  # These classes are thin wrappers around the Rust FFI layer.
  # All application logic should remain in Ruby; these are "dumb pipes"
  # for platform-native operations only.
  #
  # ## Thread Safety
  #
  # EventLoop, Window, and WebView are main-thread-only types. They use
  # Tauri's pattern of `unsafe impl Send` with the invariant that all
  # access happens on the main thread via the event loop callback.
  #
  # Only Proxy is genuinely Send-safe and can be shared with Worker Ractors.
  #
  # @example Basic usage
  #   event_loop = Tokra::Native::EventLoop.new
  #   proxy = event_loop.create_proxy
  #
  #   window = Tokra::Native::Window.new(event_loop)
  #   window.set_title("My App")
  #   window.set_size(800, 600)
  #
  #   ipc_handler = Ractor.shareable_proc { |msg| puts msg }
  #   webview = Tokra::Native::WebView.new(window, "https://example.com", ipc_handler, proxy)
  #
  #   event_loop.run do |event|
  #     case event
  #     when Tokra::Native::IpcEvent
  #       puts "IPC: #{event.message}"
  #     when Tokra::Native::WakeUpEvent
  #       puts "Wake: #{event.payload}"
  #     when Tokra::Native::WindowCloseEvent
  #       puts "Goodbye!"
  #     end
  #   end
  #
  # @see Tokra::Native::EventLoop
  # @see Tokra::Native::Window
  # @see Tokra::Native::WebView
  # @see Tokra::Native::Proxy
  module Native
    # Native classes defined in Rust extension:
    #
    # - EventLoop: Main thread event loop
    #   - .new -> EventLoop
    #   - #create_proxy -> Proxy (must call before #run)
    #   - #run(callback) -> never returns; raises SystemExit with the
    #     loop's exit code when the loop ends
    #
    # - Window: Native window
    #   - .new(event_loop) -> Window
    #   - #set_title(string)
    #   - #set_size(width, height)
    #   - #id -> String
    #
    # - WebView: WebKit/WebView2 webview
    #   - .new(window, url, ipc_callback, proxy) -> WebView
    #   - #eval(js_string)
    #
    # - Proxy: Thread-safe handle (genuinely Send-safe)
    #   - #wake_up(payload) - Send wake event to main thread
    #
    # - IpcEvent: Event fired when WebView sends IPC message
    #   - #message -> String
    #
    # - WakeUpEvent: Event fired when Proxy#wake_up is called
    #   - #payload -> String
    #
    # - WindowCloseEvent: Event fired when window close is requested

    # Generates JavaScript code to emit an event to the WebView.
    #
    # Uses Tauri's emit_js_script format, extracted at build time from
    # vendor/tauri/crates/tauri/src/event/mod.rs via `rake sync:tauri`.
    #
    # == Parameters
    #
    # +event+:: Event name (e.g., "log://log")
    # +payload+:: JSON-encoded payload string
    #
    # == Returns
    #
    # JavaScript string to execute in WebView.
    def self.emit_js_script(event, payload)
      @emit_template ||= load_js_template("emit.js.erb")
      format(@emit_template,
        emit_fn: "__TAURI_EMIT__",
        event:,
        payload:,
        ids: "[]")
    end

    # Loads a JS template from lib/tokra/js/.
    def self.load_js_template(name)
      dir = __dir__.to_s
      path = File.join(dir, "js", name)
      unless File.exist?(path)
        # Check if we're in a development checkout vs installed gem
        if File.exist?(File.join(dir, "..", "..", "Rakefile"))
          raise LoadError, "JS template not found: #{path}. Run: bundle exec rake sync:tauri"
        else
          raise LoadError, "JS template missing from gem. Try reinstalling: gem install tokra"
        end
      end
      File.read(path).lines.reject { |l| l.start_with?("//") }.join.strip
    end
  end
end
