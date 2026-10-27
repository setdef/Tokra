# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for window_handle_test.rb: a real window's raw handles
# (ADR 013). It needs no page, so it runs on Windows too.
#
# Once the loop runs, a background thread reads the window's handle and
# the display's, as a library on another thread would, and the main thread
# reads them too and follows them to the window system: the window's title
# through the handle (AppKit's -[NSView window], Win32's GetWindowTextW,
# or xdotool for an X11 window ID) and, on X11, the display's name through
# Xlib. It prints REPORT <json> and exits; at_exit then prints LATE <json>,
# what a thread's window_handle raises once the loop is gone.
#
#   bundle exec ruby test/integration/fixtures/window_handle/app.rb

require_relative "../../support/fixture_app"
require "fiddle"
require "open3"

$stdout.sync = true

module WindowHandleFixture
  # A title no other window on the display has, so xdotool's answer is
  # this window's.
  TITLE = "Tokra integration: window handle #{Process.pid}".freeze

  # +value+'s class and fields, or what reading it raised.
  def self.attempt
    value = yield
    { "kind" => value.class.name.split("::").last }.merge(value.to_h.transform_keys(&:to_s))
  rescue => e
    { "error" => e.class.name, "message" => e.message }
  end

  # The title the window system reports for the window +handle+ names,
  # read through the handle. Runs on the main thread, which owns the
  # window.
  def self.native_title(handle)
    case handle
    in Tokra::RawWindowHandle::AppKitWindowHandle(ns_view:) then appkit_title(ns_view)
    in Tokra::RawWindowHandle::Win32WindowHandle(hwnd:) then win32_title(hwnd)
    in Tokra::RawWindowHandle::XlibWindowHandle(window:) then xdotool_title(window)
    else nil
    end
  end

  # The X11 display name of the Xlib Display at +address+, read through
  # XDisplayString, which follows the pointer.
  def self.xlib_display_name(address)
    xlib = Fiddle.dlopen("libX11.so.6")
    name = Fiddle::Function.new(xlib["XDisplayString"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    name.call(address).to_s
  end

  # -[[NSView window] title], as UTF-8.
  def self.appkit_title(ns_view)
    objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    sel = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    send = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    window = send.call(ns_view, sel.call("window"))
    title = send.call(window, sel.call("title"))
    send.call(title, sel.call("UTF8String")).to_s.force_encoding(Encoding::UTF_8)
  end

  # GetWindowTextW(hwnd), as UTF-8.
  def self.win32_title(hwnd)
    user32 = Fiddle.dlopen("user32")
    text = Fiddle::Function.new(user32["GetWindowTextW"],
      [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    buffer = Fiddle::Pointer.malloc(512 * 2, Fiddle::RUBY_FREE)
    length = text.call(hwnd, buffer, 512)
    buffer.to_str(length * 2).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
  end

  # What xdotool reports as the name of the X11 window +id+, or +nil+
  # without xdotool.
  def self.xdotool_title(id)
    output, status = Open3.capture2("xdotool", "getwindowname", id.to_s, err: File::NULL)
    status.success? ? output.chomp : nil
  rescue Errno::ENOENT
    nil
  end
end

app = Tokra::Builder.default.title(WindowHandleFixture::TITLE).size(320, 240).build
window = nil

at_exit do
  late = Thread.new { WindowHandleFixture.attempt { window.window_handle } }.value
  puts "LATE #{JSON.generate(late)}"
end

app.run do |handle, event|
  next unless event.is_a?(Tokra::RunEvent::Ready)

  window = handle.get_window("main")
  Thread.new do
    report = {
      "title" => WindowHandleFixture::TITLE,
      "display_env" => ENV.fetch("DISPLAY", nil),
      "thread_window" => WindowHandleFixture.attempt { window.window_handle },
      "thread_display" => WindowHandleFixture.attempt { window.display_handle },
    }
    answers = Thread::Queue.new
    handle.run_on_main_thread do
      handle_on_main = window.window_handle
      display = handle.display_handle
      main = {
        "main_window" => WindowHandleFixture.attempt { handle_on_main },
        "main_display" => WindowHandleFixture.attempt { display },
        "app_display" => WindowHandleFixture.attempt { app.display_handle },
        "native_title" => WindowHandleFixture.native_title(handle_on_main),
      }
      if display.is_a?(Tokra::RawWindowHandle::XlibDisplayHandle) && display.display
        main["xlib_display_name"] = WindowHandleFixture.xlib_display_name(display.display)
      end
      answers << main
    rescue => e
      answers << { "error" => "#{e.class}: #{e.message}" }
    end
    report.merge!(answers.pop)
    puts "REPORT #{JSON.generate(report)}"
    handle.run_on_main_thread { handle.exit(0) }
  end
end
