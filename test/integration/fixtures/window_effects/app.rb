# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for window_effects_test.rb: a real window's effects, taskbar,
# title bar, and the app's theme (plan 045). It needs no page, so it runs
# on Windows too.
#
# Once the loop runs, a background thread changes the window through
# Tokra::Window and Tokra::AppHandle, as an app's code on another thread
# would, and reads back what the platform reports: on macOS through
# AppKit with Fiddle, on Windows through DWM, and everywhere through the
# window's theme. It never asks for focus, and it clears the Dock badge
# and progress it sets. It prints REPORT <json> and exits.
#
#   bundle exec ruby test/integration/fixtures/window_effects/app.rb

require_relative "../../support/fixture_app"
require "fiddle"

module WindowEffectsFixture
  # Seconds to wait for a change to show: the fixture's patience, since
  # each wait ends as soon as the change shows, and only a change that
  # never comes waits it out.
  SETTLE = FixtureApp::PATIENCE

  # window-vibrancy's tag for the view it adds (0.6.0
  # src/macos/internal.rs:13).
  BLUR_VIEW_TAG = 91_376_254

  # NSWindowStyleMaskFullSizeContentView.
  FULL_SIZE_CONTENT_VIEW = 1 << 15

  # DWMWA_SYSTEMBACKDROP_TYPE and DWMWA_MICA_EFFECT (window-vibrancy
  # src/windows.rs:293-294).
  SYSTEMBACKDROP_TYPE = 38
  MICA_EFFECT = 1029

  # Reads the block until it answers +expected+, or SETTLE seconds pass,
  # and answers what it read last. Each read that ends the wait prints
  # PROGRESS settled, so RealApp sees the fixture move between reads.
  def self.settle(expected)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SETTLE
    loop do
      value = yield
      if value == expected || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        FixtureApp.progress("settled")
        return value
      end

      sleep 0.05
    end
  rescue => e
    "#{e.class}: #{e.message}"
  end

  # Runs +read+ on the main thread and answers its value.
  def self.on_main(handle, &read)
    answers = Thread::Queue.new
    handle.run_on_main_thread do
      answers << read.call
    rescue => e
      answers << "#{e.class}: #{e.message}"
    end
    answers.pop
  end

  # Objective-C messages through Fiddle, each returning +type+.
  class ObjC
    def initialize
      objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
      @sel = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @get_class = Fiddle::Function.new(objc["objc_getClass"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @send = objc["objc_msgSend"]
    end

    def klass(name) = @get_class.call(name)

    # +receiver+'s answer to +selector+ with +args+, all pointers or
    # Integers, as +type+.
    def call(receiver, selector, *args, type: Fiddle::TYPE_VOIDP)
      function = Fiddle::Function.new(@send, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP] + args.map { Fiddle::TYPE_LONG },
        type)
      function.call(receiver, @sel.call(selector), *args)
    end

    def flag(receiver, selector) = call(receiver, selector, type: Fiddle::TYPE_CHAR) & 0xFF != 0
    def text(string) = string.null? ? nil : call(string, "UTF8String").to_s
  end

  # What AppKit shows of the window effect: whether window-vibrancy's
  # tagged view is in the content view, with its class, material, and
  # state; +nil+ on other platforms.
  def self.appkit_effect(window)
    handle = window.window_handle
    return nil unless handle.is_a?(Tokra::RawWindowHandle::AppKitWindowHandle)

    objc = ObjC.new
    content = objc.call(objc.call(handle.ns_view, "window"), "contentView")
    view = objc.call(content, "viewWithTag:", BLUR_VIEW_TAG)
    return { "present" => false } if view.null?

    {
      "present" => true,
      "class" => objc.text(objc.call(objc.call(view, "className"), "self")),
      "material" => objc.call(view, "material", type: Fiddle::TYPE_LONG),
      "state" => objc.call(view, "state", type: Fiddle::TYPE_LONG),
    }
  end

  # The Dock tile's badge label and its progress indicator's value and
  # visibility, as tao leaves them; +nil+ off macOS.
  def self.appkit_dock_tile
    return nil unless RbConfig::CONFIG["host_os"].include?("darwin")

    objc = ObjC.new
    tile = objc.call(objc.call(objc.klass("NSApplication"), "sharedApplication"), "dockTile")
    content = objc.call(tile, "contentView")
    indicator = nil
    unless content.null?
      subviews = objc.call(content, "subviews")
      count = objc.call(subviews, "count", type: Fiddle::TYPE_LONG)
      count.times do |index|
        view = objc.call(subviews, "objectAtIndex:", index)
        indicator = view if objc.call(view, "isKindOfClass:", objc.klass("NSProgressIndicator").to_i,
          type: Fiddle::TYPE_CHAR) & 0xFF != 0
      end
    end
    {
      "badge" => objc.text(objc.call(tile, "badgeLabel")),
      "progress" => indicator && objc.call(indicator, "doubleValue", type: Fiddle::Types::DOUBLE),
      "progress_hidden" => indicator && objc.flag(indicator, "isHidden"),
    }
  end

  # Whether AppKit draws the title bar transparent and lets the content
  # view fill the window; +nil+ off macOS.
  def self.appkit_title_bar(window)
    handle = window.window_handle
    return nil unless handle.is_a?(Tokra::RawWindowHandle::AppKitWindowHandle)

    objc = ObjC.new
    ns_window = objc.call(handle.ns_view, "window")
    {
      "transparent" => objc.flag(ns_window, "titlebarAppearsTransparent"),
      "full_size" => objc.call(ns_window, "styleMask", type: Fiddle::TYPE_LONG) & FULL_SIZE_CONTENT_VIEW != 0,
    }
  end

  # The app's theme as each platform keeps it: on macOS NSApp's
  # appearance (tao platform_impl/macos/window.rs:383-401), on Linux GTK's
  # dark preference (platform_impl/linux/event_loop.rs:949-956), and on
  # Windows the window's theme, which tao's loop sends each window
  # (platform_impl/windows/event_loop.rs:344-349).
  def self.app_theme(window)
    host = RbConfig::CONFIG["host_os"]
    if host.include?("darwin")
      objc = ObjC.new
      appearance = objc.call(objc.call(objc.klass("NSApplication"), "sharedApplication"), "appearance")
      appearance.null? ? nil : objc.text(objc.call(appearance, "name"))
    elsif host.include?("linux")
      gtk_prefers_dark
    else
      window.theme.name
    end
  end

  # GTK's gtk-application-prefer-dark-theme setting, read with g_object_get.
  def self.gtk_prefers_dark
    gtk = Fiddle.dlopen("libgtk-3.so.0")
    settings = Fiddle::Function.new(gtk["gtk_settings_get_default"], [], Fiddle::TYPE_VOIDP).call
    get = Fiddle::Function.new(gtk["g_object_get"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VARIADIC],
      Fiddle::TYPE_VOID)
    value = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    value[0, 4] = [0].pack("l")
    get.call(settings, "gtk-application-prefer-dark-theme", :voidp, value, :voidp, nil)
    value[0, 4].unpack1("l") != 0
  end

  # The Windows build number, from RtlGetVersion's OSVERSIONINFOW.
  def self.windows_build
    ntdll = Fiddle.dlopen("ntdll.dll")
    get_version = Fiddle::Function.new(ntdll["RtlGetVersion"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    info = Fiddle::Pointer.malloc(276, Fiddle::RUBY_FREE)
    info[0, 4] = [276].pack("L")
    get_version.call(info)
    info[12, 4].unpack1("L")
  end

  # What DWM reports for +attribute+ of the window, or the failing
  # HRESULT as a String.
  def self.dwm_attribute(window, attribute)
    dwmapi = Fiddle.dlopen("dwmapi.dll")
    get = Fiddle::Function.new(dwmapi["DwmGetWindowAttribute"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    value = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    value[0, 4] = [0].pack("l")
    result = get.call(window.window_handle.hwnd, attribute, value, 4)
    result.zero? ? value[0, 4].unpack1("l") : format("HRESULT 0x%08x", result & 0xFFFFFFFF)
  end

  # The backdrop DWM reports, read where window-vibrancy sets it: the
  # system backdrop type from build 22523, the undocumented Mica flag
  # from 22000; +nil+ elsewhere.
  def self.dwm_backdrop(window)
    return nil unless window.window_handle.is_a?(Tokra::RawWindowHandle::Win32WindowHandle)

    build = windows_build
    if build >= 22_523 then {
"build" => build,
"attribute" => SYSTEMBACKDROP_TYPE,
"value" => dwm_attribute(window, SYSTEMBACKDROP_TYPE),
}
    elsif build >= 22_000 then {
"build" => build,
"attribute" => MICA_EFFECT,
"value" => dwm_attribute(window, MICA_EFFECT),
}
    else { "build" => build }
    end
  end
end

app = Tokra::Builder.default.build(Tokra.generate_context)
FixtureApp.background(app)

app.run do |handle, event|
  next unless event.is_a?(Tokra::RunEvent::Ready)

  window = handle.get_window("main")
  Thread.new do
    report = {}
    fixture = WindowEffectsFixture
    report["webviews"] = window.webviews.map(&:label)

    # Effects: macOS's first material and Windows' first effect; nil
    # clears Windows' and leaves macOS's (vibrancy/mod.rs:15-30).
    window.set_effects(Tokra::EffectsBuilder.new.effect(Tokra::Effect::Mica).effect(Tokra::Effect::Popover)
      .effect(Tokra::Effect::Sidebar).state(Tokra::EffectState::Active).radius(6).build)
    report["effect"] = fixture.on_main(handle) { fixture.appkit_effect(window) }
    report["backdrop"] = fixture.on_main(handle) { fixture.dwm_backdrop(window) }
    window.set_effects(nil)
    report["effect_after_nil"] = fixture.on_main(handle) { fixture.appkit_effect(window) }
    report["backdrop_after_nil"] = fixture.on_main(handle) { fixture.dwm_backdrop(window) }

    # The Dock tile on macOS; elsewhere each runs without error.
    window.set_badge_count(5)
    report["badge_count"] = fixture.on_main(handle) { fixture.appkit_dock_tile&.fetch("badge") }
    if window.respond_to?(:set_badge_label)
      window.set_badge_label("New")
      report["badge_label"] = fixture.on_main(handle) { fixture.appkit_dock_tile&.fetch("badge") }
    end
    window.set_badge_count(nil)
    report["badge_cleared"] = fixture.on_main(handle) { fixture.appkit_dock_tile&.fetch("badge") }
    window.set_progress_bar(Tokra::ProgressBarState.new(status: Tokra::ProgressBarStatus::Normal, progress: 40))
    report["progress"] = fixture.on_main(handle) { fixture.appkit_dock_tile }
    window.set_progress_bar(Tokra::ProgressBarState.new(status: Tokra::ProgressBarStatus::None))
    report["progress_none"] = fixture.on_main(handle) { fixture.appkit_dock_tile }
    if window.respond_to?(:set_overlay_icon)
      window.set_overlay_icon(Tokra::Image.new(rgba: "\x20\x40\x80\xFF".b * 256, width: 16, height: 16))
      window.set_overlay_icon(nil)
      report["overlay_icon"] = fixture.on_main(handle) { "set" }
    end

    # The title bar styles, as Tauri pairs them (lib.rs:3511-3534).
    report["title_bar"] = Tokra::TitleBarStyle.constants.sort.to_h do |name|
      window.set_title_bar_style(Tokra::TitleBarStyle.const_get(name))
      [name.to_s, fixture.on_main(handle) { fixture.appkit_title_bar(window) || "set" }]
    end

    # The app's theme, which each window shows (app.rs:842-869).
    # GTK takes the theme on a later turn of its main loop, so each read
    # waits for the answer the platform should give.
    host = RbConfig::CONFIG["host_os"]
    # On Windows nil follows the system's theme, which the fixture cannot
    # know, so only macOS and Linux read it back.
    themes = [Tokra::Theme::Dark, Tokra::Theme::Light]
    themes << nil if host.include?("darwin") || host.include?("linux")
    report["app_theme"] = themes.map do |theme|
      handle.set_theme(theme)
      expected = if host.include?("darwin")
        { "Dark" => "NSAppearanceNameDarkAqua", "Light" => "NSAppearanceNameAqua" }[theme&.name]
      elsif host.include?("linux")
        theme == Tokra::Theme::Dark
      else
        theme&.name
      end
      fixture.settle(expected) { fixture.on_main(handle) { fixture.app_theme(window) } }
    end

    puts "REPORT #{JSON.generate(report)}"
  rescue => e
    puts "REPORT #{JSON.generate('error' => "#{e.class}: #{e.message}", 'backtrace' => e.backtrace.first(5))}"
  ensure
    handle.exit(0)
  end
end
