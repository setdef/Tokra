# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for window_state_test.rb: a real window's getters and setters
# (plans 040 and 041). It needs no page, so it runs on Windows too.
#
# Once the loop runs, a background thread changes the window through
# Tokra::Window, as an app's code on another thread would, and reads back
# what the platform reports through the getters. tao applies many macOS
# changes asynchronously, so each read waits until the expected answer
# shows or two seconds pass, and records what it last saw. It never asks
# for focus, fullscreen, or a minimized window, and maximizes only on
# Windows: on macOS each would move or cover the screen of the person
# running the suite, and on Linux the tests run under Xvfb with no window
# manager to grant them. It prints REPORT <json> and exits.
#
#   bundle exec ruby test/integration/fixtures/window_state/app.rb

require_relative "../../support/fixture_app"
require "fiddle"

$stdout.sync = true

module WindowStateFixture
  # Seconds to wait for a change to show.
  SETTLE = 2

  # Reads the block until it answers +expected+ (or anything, without
  # one), or SETTLE seconds pass, and answers what it read last as JSON.
  def self.settle(expected = nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SETTLE
    loop do
      value = yield
      return json(value) if expected.nil? || value == expected
      return json(value) if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  rescue => e
    { "error" => "#{e.class}: #{e.message}" }
  end

  # +value+ as JSON: a Data as its fields, a Hash and an Array with their
  # members as JSON, and the rest as itself.
  def self.json(value)
    case value
    when Data then json(value.to_h)
    when Hash then value.to_h { |key, field| [key.to_s, json(field)] }
    when Array then value.map { |item| json(item) }
    else value
    end
  end

  # What AppKit reports as the window's content minimum and maximum sizes,
  # in points, read through its AppKit handle on the main thread; +nil+
  # on other platforms.
  def self.appkit_content_limits(window)
    handle = window.window_handle
    return nil unless handle.is_a?(Tokra::RawWindowHandle::AppKitWindowHandle)

    objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    sel = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    send = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    # NSSize is two doubles, returned in registers on arm64 and x86_64.
    size = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
      Fiddle::Types::DOUBLE)
    ns_window = send.call(handle.ns_view, sel.call("window"))
    {
      "min_width" => size.call(ns_window, sel.call("contentMinSize")),
      "max_width" => size.call(ns_window, sel.call("contentMaxSize")),
    }
  end

  # What AppKit reports as the visible frame of the window's screen, the
  # part without the menu bar and the Dock, in points, as
  # <tt>{ "width" =>, "height" => }</tt>; +nil+ on other platforms. Fiddle
  # cannot take an NSRect back from objc_msgSend, so this asks key-value
  # coding for it boxed in an NSValue and reads its description,
  # "NSRect: {{x, y}, {width, height}}".
  def self.appkit_visible_frame(window)
    handle = window.window_handle
    return nil unless handle.is_a?(Tokra::RawWindowHandle::AppKitWindowHandle)

    objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    sel = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    get_class = Fiddle::Function.new(objc["objc_getClass"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    send = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    send_with = Fiddle::Function.new(objc["objc_msgSend"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    key = send_with.call(get_class.call("NSString"), sel.call("stringWithUTF8String:"), "visibleFrame")
    screen = send.call(send.call(handle.ns_view, sel.call("window")), sel.call("screen"))
    boxed = send_with.call(screen, sel.call("valueForKey:"), key)
    text = send.call(send.call(boxed, sel.call("description")), sel.call("UTF8String")).to_s
    width, height = text.scan(/-?[\d.]+/).map(&:to_f).last(2)
    { "width" => width, "height" => height }
  end

  # Whether AppKit draws the window's shadow, read through its AppKit
  # handle on the main thread; +nil+ on other platforms.
  def self.appkit_has_shadow(window)
    handle = window.window_handle
    return nil unless handle.is_a?(Tokra::RawWindowHandle::AppKitWindowHandle)

    objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    sel = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    send = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    # BOOL is one byte, returned in the low byte of the result register.
    flag = Fiddle::Function.new(objc["objc_msgSend"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_CHAR)
    ns_window = send.call(handle.ns_view, sel.call("window"))
    flag.call(ns_window, sel.call("hasShadow")) & 0xFF != 0
  end

  # Runs +read+ on the main thread and answers its value.
  def self.on_main(handle, &read)
    answers = Thread::Queue.new
    handle.run_on_main_thread do
      answers << read.call
    rescue => e
      answers << { "error" => "#{e.class}: #{e.message}" }
    end
    answers.pop
  end
end

app = Tokra::Builder.default.title("Tokra integration: window state").size(320, 240).build
FixtureApp.background(app)
WINDOWS = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)

app.run do |handle, event|
  next unless event.is_a?(Tokra::RunEvent::Ready)

  window = handle.get_window("main")
  Thread.new do
    report = {}
    fixture = WindowStateFixture
    scale = window.scale_factor
    monitor = window.current_monitor
    report["scale_factor"] = scale
    report["current_monitor"] = fixture.json(monitor)
    report["primary_monitor"] = fixture.json(window.primary_monitor)
    report["available_monitors"] = fixture.json(window.available_monitors)
    report["monitor_at_window"] = fixture.settle do
      position = window.outer_position
      window.monitor_from_point(position.x, position.y)
    end
    report["main_thread_scale_factor"] = fixture.on_main(handle) { window.scale_factor }
    report["appkit_visible_frame"] = fixture.on_main(handle) { fixture.appkit_visible_frame(window) }

    window.set_size(Tokra::LogicalSize.new(width: 300, height: 200))
    expected = Tokra::LogicalSize.new(width: 300, height: 200).to_physical(scale)
    expected = Tokra::PhysicalSize.new(width: expected.width.round, height: expected.height.round)
    report["logical_size"] = fixture.settle(expected) { window.inner_size }
    report["logical_size_expected"] = fixture.json(expected)

    expected = Tokra::PhysicalSize.new(width: 500, height: 360)
    window.set_size(expected)
    report["physical_size"] = fixture.settle(expected) { window.inner_size }
    report["outer_size"] = fixture.json(window.outer_size)

    window.set_position(Tokra::LogicalPosition.new(x: 120, y: 140))
    expected = Tokra::PhysicalPosition.new(x: (120 * scale).round, y: (140 * scale).round)
    report["logical_position"] = fixture.settle(expected) { window.outer_position }
    report["logical_position_expected"] = fixture.json(expected)
    report["inner_position"] = fixture.json(window.inner_position)

    window.set_min_size(Tokra::LogicalSize.new(width: 150, height: 100))
    window.set_max_size(Tokra::LogicalSize.new(width: 900, height: 700))
    report["appkit_limits"] = fixture.on_main(handle) do
      sleep 0.2
      fixture.appkit_content_limits(window)
    end

    flags = {
      "resizable" => %i[set_resizable is_resizable],
      "maximizable" => %i[set_maximizable is_maximizable],
      "minimizable" => %i[set_minimizable is_minimizable],
      "closable" => %i[set_closable is_closable],
      "decorated" => %i[set_decorations is_decorated],
      "always_on_top" => %i[set_always_on_top is_always_on_top],
    }
    # Each flag starts true, except always on top; the setter flips it and
    # flips it back.
    report["flags"] = flags.to_h do |name, (setter, getter)|
      changed_to = name == "always_on_top"
      window.public_send(setter, changed_to)
      changed = fixture.settle(changed_to) { window.public_send(getter) }
      on_main = fixture.on_main(handle) { window.public_send(getter) }
      window.public_send(setter, !changed_to)
      restored = fixture.settle(!changed_to) { window.public_send(getter) }
      [name, { "changed" => changed, "on_main" => on_main, "restored" => restored }]
    end

    window.hide
    hidden = fixture.settle(false) { window.is_visible }
    window.show
    report["visible"] = { "hidden" => hidden, "shown" => fixture.settle(true) { window.is_visible } }

    window.set_theme(Tokra::Theme::Dark)
    dark = fixture.settle(Tokra::Theme::Dark) { window.theme }
    window.set_theme(Tokra::Theme::Light)
    report["theme"] = { "dark" => dark, "light" => fixture.settle(Tokra::Theme::Light) { window.theme } }
    window.set_theme(nil)

    window.center
    report["centered"] = fixture.settle do
      sleep 0.3
      {
"outer_position" => window.outer_position,
"outer_size" => window.outer_size,
"work_area" => window.current_monitor&.work_area,
}
    end

    if WINDOWS
      window.maximize
      maximized = fixture.settle(true) { window.is_maximized }
      window.unmaximize
      report["maximized"] = { "maximized" => maximized, "restored" => fixture.settle(false) { window.is_maximized } }
    end

    # Plan 041: Tauri's WindowExt enabled state.
    window.set_enabled(false)
    disabled = fixture.settle(false) { window.is_enabled }
    disabled_on_main = fixture.on_main(handle) { window.is_enabled }
    window.set_enabled(true)
    report["enabled"] = {
      "disabled" => disabled,
      "disabled_on_main" => disabled_on_main,
      "enabled" => fixture.settle(true) { window.is_enabled },
    }

    # Size constraints one side at a time: on macOS AppKit's content
    # limits; everywhere the width a smaller size then reaches. Only GTK
    # holds a resize Tokra asks for to the minimum (geometry hints, tao
    # platform_impl/linux/util.rs:40). On macOS tao
    # resizes with setContentSize (platform_impl/macos/util/async.rs:87-92),
    # which AppKit's minimum does not limit; on Windows tao answers
    # WM_WINDOWPOSCHANGING itself (platform_impl/windows/event_loop.rs:
    # 1151-1236), so DefWindowProc never applies the minimum that
    # WM_GETMINMAXINFO gives (:1861-1889) to a SetWindowPos, only to a
    # person's drag. Each read waits for its platform's answer.
    window.set_size_constraints(Tokra::WindowSizeConstraints.new(
      min_width: Tokra::LogicalUnit.new(260),
      max_width: Tokra::PhysicalUnit.new((880 * scale).round)
    ))
    report["constraint_limits"] = fixture.on_main(handle) do
      sleep 0.2
      fixture.appkit_content_limits(window)
    end
    window.set_size(Tokra::LogicalSize.new(width: 100, height: 220))
    held = RbConfig::CONFIG["host_os"].include?("linux")
    expected = ((held ? 260 : 100) * scale).round
    report["constrained_width"] = fixture.settle(expected) { window.inner_size.width }
    report["constrained_expected_width"] = expected
    window.set_size_constraints(Tokra::WindowSizeConstraints.new)

    window.set_shadow(false)
    without = fixture.on_main(handle) { fixture.appkit_has_shadow(window) }
    window.set_shadow(true)
    report["shadow"] = { "without" => without, "with" => fixture.on_main(handle) { fixture.appkit_has_shadow(window) } }

    image = Tokra::Image.new(rgba: "\x20\x40\x80\xFF".b * 256, width: 16, height: 16)
    report["icon"] = fixture.settle { window.set_icon(image) }
    begin
      window.set_icon(Tokra::Image.new(rgba: "\x00".b * 12, width: 2, height: 2))
    rescue Tokra::Error::Runtime => e
      report["bad_icon"] = e.message
    end
    report["background_color"] = fixture.settle do
      window.set_background_color(Tokra::Color.from_str("#1e1e1e"))
      handle.get_webview("main").set_background_color(Tokra::Color.new(30, 30, 30, 255))
      fixture.on_main(handle) { "set" }
    end
    window.set_background_color(nil)

    # Plan 041: the app handle's monitors and cursor come from the event
    # loop's window target, from this thread and from the main one.
    position = window.outer_position
    report["handle_monitors"] = {
      "primary" => fixture.json(handle.primary_monitor) == fixture.json(window.primary_monitor),
      "available" => fixture.json(handle.available_monitors) == fixture.json(window.available_monitors),
      "at_window" => fixture.json(handle.monitor_from_point(position.x, position.y)) ==
        fixture.json(window.monitor_from_point(position.x, position.y)),
      "on_main" => fixture.on_main(handle) { fixture.json(handle.available_monitors) } ==
        fixture.json(window.available_monitors),
    }
    report["cursor"] = fixture.settle do
      {
        "handle" => handle.cursor_position.class.name,
        "window" => window.cursor_position.class.name,
        "on_main" => fixture.on_main(handle) { handle.cursor_position.class.name },
      }
    end

    report["fullscreen"] = window.is_fullscreen
    report["minimized"] = window.is_minimized
    puts "REPORT #{JSON.generate(report)}"
  rescue => e
    puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(5))}"
  ensure
    handle.exit(0)
  end
end
