# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Stubs for the Native (Rust FFI) boundary.
# EventLoop is configured per-test via thread-local to inject events.
module StubNative
  # Thread-local event queue for test injection
  def self.inject_event(event)
    Thread.current[:stub_native_event] = event
  end

  def self.clear_event
    Thread.current[:stub_native_event] = nil
    Thread.current[:stub_native_responses] = nil
    Thread.current[:stub_native_dropped] = nil
    Thread.current[:stub_native_windows] = nil
    Thread.current[:stub_native_webviews] = nil
    Thread.current[:stub_native_task_wake_ups] = nil
    Thread.current[:stub_native_event_loop_calls] = nil
    Thread.current[:stub_native_exit_code] = nil
    Thread.current[:stub_native_nsapp_calls] = nil
    Thread.current[:stub_native_trays] = nil
    Thread.current[:stub_native_tray_failure] = nil
  end

  # The status the loop ended with: the code of the exit request the App
  # accepted, 0 for the last window gone, or +nil+ when the loop simply ran
  # out of events.
  def self.exit_code
    Thread.current[:stub_native_exit_code]
  end

  # The calls the event loops received across the run, in order:
  # <tt>[:set_activation_policy, name]</tt> and <tt>[:run]</tt>.
  def self.event_loop_calls
    Thread.current[:stub_native_event_loop_calls] ||= []
  end

  # How many times Proxy#send_task woke the loop across the run.
  def self.task_wake_ups
    Thread.current[:stub_native_task_wake_ups] ||= 0
  end

  # Windows created across the run, recording their title and size.
  def self.windows
    Thread.current[:stub_native_windows] ||= []
  end

  # Protocol responses recorded across the run, observable by tests
  # (the proxy is created inside App#run, so the sink is module-level).
  def self.responses
    Thread.current[:stub_native_responses] ||= []
  end

  # Request ids dropped without a reply (ipc:// key mismatch path),
  # observable by tests the same way as responses.
  def self.dropped
    Thread.current[:stub_native_dropped] ||= []
  end

  # The real muda-backed menu classes: they need no window and no
  # display, so tests drive real menus (plan 042, Verification).
  Menu = Tokra::Native::Menu
  Submenu = Tokra::Native::Submenu
  MenuItem = Tokra::Native::MenuItem
  CheckMenuItem = Tokra::Native::CheckMenuItem
  PredefinedMenuItem = Tokra::Native::PredefinedMenuItem
  IconMenuItem = Tokra::Native::IconMenuItem
  MenuIcon = Tokra::Native::MenuIcon

  # The NSApp calls the app made, in order, as <tt>[name, id]</tt>.
  def self.nsapp_calls
    Thread.current[:stub_native_nsapp_calls] ||= []
  end

  # On macOS, records the calls that would change NSApp, which a test
  # process must not touch: tao makes NSApp with its own class, and a
  # plain one made first would break every later event loop.
  if Tokra::Native.respond_to?(:init_menu_for_nsapp)
    def self.init_menu_for_nsapp(menu)
      nsapp_calls << [:init_menu_for_nsapp, menu.id]
      nil
    end

    def self.remove_menu_for_nsapp(menu)
      nsapp_calls << [:remove_menu_for_nsapp, menu.id]
      nil
    end

    def self.set_windows_menu_for_nsapp(submenu)
      nsapp_calls << [:set_windows_menu_for_nsapp, submenu.id]
      nil
    end

    def self.set_help_menu_for_nsapp(submenu)
      nsapp_calls << [:set_help_menu_for_nsapp, submenu.id]
      nil
    end
  end

  # A tray-icon tray that records each call as <tt>[name, argument, main
  # thread?]</tt> (plan 043, Verification): a real status item would make
  # AppKit's NSApplication before tao's in this process. Its icon class is
  # the real one, which is plain data. The platform's own setters exist
  # only where Native::TrayIcon has them, so respond_to? answers as the
  # real class does.
  class TrayIcon
    Icon = Tokra::Native::TrayIcon::Icon

    # The trays built on this thread, in order.
    def self.instances
      Thread.current[:stub_native_trays] ||= []
    end

    # The message the next build raises as a RuntimeError, as tray-icon's
    # errors reach Ruby, or +nil+.
    def self.fail_next=(message)
      Thread.current[:stub_native_tray_failure] = message
    end

    def self.new(id, attributes)
      message = Thread.current[:stub_native_tray_failure]
      Thread.current[:stub_native_tray_failure] = nil
      raise message if message

      super.tap { |tray| instances << tray }
    end

    attr_reader :id, :attributes, :calls

    def initialize(id, attributes)
      @id = id
      @attributes = attributes
      @main_thread = Thread.current == Thread.main
      @calls = []
      @removed = false
    end

    # Whether the tray was built on the main thread.
    def built_on_main_thread? = @main_thread

    def removed? = @removed

    def remove
      @removed = true
      record(:remove, nil)
    end

    def rect = @removed ? nil : [10, 20, 22, 24]

    %i[set_icon set_menu set_tooltip set_title set_visible].each do |name|
      define_method(name) { |value| record(name, value) }
    end

    %i[set_temp_dir_path set_icon_as_template set_show_menu_on_left_click].each do |name|
      define_method(name) { |value| record(name, value) } if Tokra::Native::TrayIcon.method_defined?(name)
    end

    private def record(name, value)
      @calls << [name, value, Thread.current == Thread.main] unless @removed && name != :remove
      nil
    end
  end

  # A window's own menu bar, recorded as <tt>[name, menu id]</tt>, as
  # Native::Window answers on Windows and Linux.
  module WindowMenus
    def menu_calls
      @menu_calls ||= []
    end

    # The theme each init_menu asked for, in order.
    def menu_themes
      @menu_themes ||= []
    end

    def init_menu(menu, theme)
      @closed || ((menu_calls << [:init_menu, menu.id]) && (menu_themes << theme))
      nil
    end

    def remove_menu(menu)
      @closed || (menu_calls << [:remove_menu, menu.id])
      nil
    end

    def hide_menu(menu)
      @closed || ((menu_calls << [:hide_menu, menu.id]) && (@hidden = true))
      nil
    end

    def show_menu(menu)
      @closed || ((menu_calls << [:show_menu, menu.id]) && (@hidden = false))
      nil
    end

    # Whether the window shows a menu bar: one it was given and did not
    # hide, while it is open.
    def is_menu_visible(menu)
      !@closed && menu_calls.include?([:init_menu, menu.id]) && !@hidden
    end
  end

  # Windows' menu-bar theme, recorded as <tt>[menu id, theme]</tt>, as
  # Native::Window answers on Windows only.
  module WindowMenuThemes
    def menu_theme_calls
      @menu_theme_calls ||= []
    end

    def set_menu_theme(menu, theme)
      @closed || (menu_theme_calls << [menu.id, theme])
      nil
    end
  end

  # Context menus, recorded as <tt>[menu id, position, main thread?]</tt>.
  # A real popup tracks the pointer until it closes; this one closes at
  # once, and a closed window shows nothing, as the native one does.
  module WindowPopups
    def popups
      @popups ||= []
    end

    def popup_menu(menu, position)
      @closed || (popups << [menu.id, position, Thread.current == Thread.main])
      nil
    end
  end

  # Stub Proxy that records respond() and drop_response() calls, and
  # queues the loop's own requests as the real proxy sends them through
  # tao's channel.
  class Proxy
    def initialize(queue = [])
      @queue = queue
    end

    # Queues the request as Native::Proxy#request_exit does: the loop
    # delivers it as an ExitRequestedEvent.
    def request_exit(code)
      @queue << Tokra::Native::ExitRequestedEvent.new(code)
      nil
    end

    # Queues the window's close request, which the loop delivers as the
    # close button's WindowCloseEvent.
    def request_close
      @queue << Tokra::Native::WindowCloseEvent.new
      nil
    end

    def respond(id, status, headers, body)
      StubNative.responses << [id, status, headers, body]
    end

    def drop_response(id)
      StubNative.dropped << id
    end

    # Counts the wake-up; the test injects the Native::TaskEvent it causes.
    def send_task
      Thread.current[:stub_native_task_wake_ups] = StubNative.task_wake_ups + 1
      nil
    end
  end

  # Stub Window recording its title and size. Closing it queues its
  # WindowDestroyedEvent, as the platform answers tao's dropped window.
  class Window
    include WindowMenus if Tokra::Native::Window.method_defined?(:init_menu)
    include WindowMenuThemes if Tokra::Native::Window.method_defined?(:set_menu_theme)
    include WindowPopups

    attr_reader :size

    def initialize(event_loop)
      @queue = event_loop&.queue || []
      @closed = false
      @state = STATE.dup
      @requests = {}
      StubNative.windows << self
    end

    def closed? = @closed

    def close
      return if @closed

      @closed = true
      @queue << Tokra::Native::WindowDestroyedEvent.new
      nil
    end

    # A closed window answers +nil+, as Native::Window#title does.
    def title = @closed ? nil : @title

    def set_title(title) = @closed || @title = title
    def set_size(width, height) = @size = [width, height]
    def set_always_on_top(always_on_top) = @closed || @state[:is_always_on_top] = always_on_top
    def set_ignore_cursor_events(ignore) = @ignore_cursor_events = ignore

    # A monitor as Native::Window answers one: name, position, size, work
    # area, and scale factor (ext/tokra/src/window_state.rs).
    MONITOR = ["Stub Display", [0, 0], [3024, 1964], [[0, 74], [3024, 1890]], 2.0].freeze
    # A second monitor, to the right of the first.
    SIDE_MONITOR = [nil, [3024, 0], [1920, 1080], [[3024, 0], [1920, 1080]], 1.0].freeze

    # What the stub window reports until a setter changes it, in the shapes
    # Native::Window answers (ext/tokra/src/window_state.rs).
    STATE = {
      scale_factor: 2.0,
      inner_position: [[20, 84]],
      outer_position: [[20, 28]],
      inner_size: [1600, 1200],
      outer_size: [1600, 1256],
      is_fullscreen: false,
      is_minimized: false,
      is_maximized: false,
      is_focused: false,
      is_decorated: true,
      is_resizable: true,
      is_maximizable: true,
      is_minimizable: true,
      is_closable: true,
      is_visible: true,
      is_always_on_top: false,
      theme: "Light",
      current_monitor: [MONITOR],
      primary_monitor: [MONITOR],
      available_monitors: [MONITOR, SIDE_MONITOR].freeze,
      is_enabled: true,
    }.freeze

    # What each setter last asked for, by setter name, and the webview
    # #inner_size was last given.
    attr_reader :requests, :inner_size_webview

    # The state a getter answers, for a test to change.
    attr_reader :state

    (STATE.keys - [:inner_size]).each do |getter|
      define_method(getter) { @closed ? nil : @state.fetch(getter) }
    end

    def inner_size(webview)
      @inner_size_webview = webview
      @closed ? nil : @state.fetch(:inner_size)
    end

    def monitor_from_point(x, y)
      return nil if @closed

      [[MONITOR, SIDE_MONITOR].find { |(_, (left, top), (width, height))| x.between?(left, left + width - 1) && y.between?(top, top + height - 1) }]
    end

    # Setters that change a flag a getter reads back.
    {
set_resizable: :is_resizable,
set_maximizable: :is_maximizable,
set_minimizable: :is_minimizable,
set_closable: :is_closable,
set_maximized: :is_maximized,
set_minimized: :is_minimized,
set_visible: :is_visible,
set_decorations: :is_decorated,
set_fullscreen: :is_fullscreen,
set_simple_fullscreen: :is_fullscreen,
set_enabled: :is_enabled,
}.each do |setter, key|
      define_method(setter) do |value|
        request(setter, value) { @state[key] = value }
      end
    end

    # Setters that only record what they were asked.
    %i[
      center
      request_user_attention
      set_always_on_bottom
      set_visible_on_all_workspaces
      set_content_protection
      set_inner_size
      set_min_inner_size
      set_max_inner_size
      set_outer_position
      set_focus
      set_focusable
      set_skip_taskbar
      set_cursor_grab
      set_cursor_visible
      set_cursor_icon
      set_cursor_position
      drag_window
      drag_resize_window
      set_theme
      set_inner_size_constraints
      set_window_icon
      set_background_color
      set_shadow
    ].each do |setter|
      define_method(setter) { |*args| request(setter, *args) }
    end

    # Records a setter's arguments, and runs its change, unless closed.
    private def request(setter, *args)
      return nil if @closed

      @requests[setter] = args
      yield if block_given?
      nil
    end

    # The tagged Arrays the native window answers for its raw handles
    # (ext/tokra/src/raw_handle.rs). A stub window has no native one, so
    # by default both name raw-window-handle's Unavailable.
    attr_writer :raw_window_handle, :raw_display_handle

    def raw_window_handle = (!@closed && @raw_window_handle) || [:Unavailable]
    def raw_display_handle = (!@closed && @raw_display_handle) || [:Unavailable]
  end

  # Stub WebView factory recording initialization scripts and evals
  class WebView
    # A script whose evaluation fails, the way wry's evaluate_script can.
    FAILING_SCRIPT = "throw from wry"

    attr_reader :initialization_scripts, :evals, :background_colors

    # The error wry's set_background_color gives, for a test to set.
    attr_accessor :background_color_error

    def self.new_with_protocol(_, _, scripts) = new(scripts).tap { |webview| instances << webview }

    # Webviews created across the run.
    def self.instances
      Thread.current[:stub_native_webviews] ||= []
    end

    def initialize(scripts = [])
      @initialization_scripts = scripts
      @evals = []
      @background_colors = []
      @closed = false
    end

    def closed? = @closed

    def close
      @closed = true
      nil
    end

    # Records the color, or raises the error a test set, as wry can fail.
    def set_background_color(rgba)
      return if @closed
      raise background_color_error if background_color_error

      @background_colors << rgba
      nil
    end

    # A closed webview ignores the script, as Native::WebView#eval does.
    def eval(js)
      return if @closed
      raise "evaluation failed" if js == FAILING_SCRIPT

      @evals << js
    end
  end

  # Stub EventLoop that delivers the injected event (or events), and the
  # events the run itself queues, to the callback, then
  # LoopDestroyedEvent, the order tao's loop ends in. An exit the App
  # accepts ends the loop at once, as the native loop's answer does
  # (ext/tokra/src/event_loop.rs).
  class EventLoop
    # Events waiting for the callback; windows and proxies add to it.
    attr_reader :queue

    def initialize
      @queue = []
      @ended = false
      @cursor = [[812.0, 455.5]]
    end

    def create_proxy = Proxy.new(@queue)

    # The cursor position the window target answers, in Native::EventLoop's
    # shape: <tt>[[x, y]]</tt>, or <tt>[nil]</tt> for tao's error.
    attr_writer :cursor

    # The window target's answers, as Native::EventLoop gives them before
    # and while it runs; +nil+ once the run has ended.
    def cursor_position = @ended ? nil : @cursor
    def primary_monitor = @ended ? nil : [Window::MONITOR]
    def available_monitors = @ended ? nil : [Window::MONITOR, Window::SIDE_MONITOR]

    def monitor_from_point(x, y)
      return nil if @ended

      [[Window::MONITOR, Window::SIDE_MONITOR].find { |(_, (left, top), (width, height))| x.between?(left, left + width - 1) && y.between?(top, top + height - 1) }]
    end

    # Records the policy's name, as tao's macOS loop keeps it for launch.
    # Defined only where the real loop has it, so the stub answers
    # respond_to? as Native::EventLoop does.
    if Tokra::Native::EventLoop.method_defined?(:set_activation_policy)
      def set_activation_policy(name)
        StubNative.event_loop_calls << [:set_activation_policy, name]
        nil
      end
    end

    def run(callback)
      StubNative.event_loop_calls << [:run]
      injected = Thread.current[:stub_native_event]
      @queue.unshift(*(injected.is_a?(Array) ? injected : [injected].compact))
      while (event = @queue.shift)
        answer = callback.call(event)
        break if ends_loop?(event, answer)
      end
      callback.call(Tokra::Native::LoopDestroyedEvent.new)
    ensure
      @ended = true
    end

    # Whether the App's +answer+ to +event+ ends the loop, recording the
    # status the native loop would end with.
    private def ends_loop?(event, answer)
      return false unless answer == true

      case event
      when Tokra::Native::ExitRequestedEvent then Thread.current[:stub_native_exit_code] = event.code
      when Tokra::Native::WindowDestroyedEvent then Thread.current[:stub_native_exit_code] = 0
      else return false
      end
      true
    end
  end
end

# StubNative as a platform whose windows carry their own menu bars, as on
# Windows and Linux, wherever the tests run: no NSApp functions, and
# windows with Native::Window's menu methods.
module StubWindowMenusNative
  EventLoop = StubNative::EventLoop
  WebView = StubNative::WebView
  Proxy = StubNative::Proxy
  Menu = StubNative::Menu
  Submenu = StubNative::Submenu
  MenuItem = StubNative::MenuItem
  CheckMenuItem = StubNative::CheckMenuItem
  PredefinedMenuItem = StubNative::PredefinedMenuItem
  IconMenuItem = StubNative::IconMenuItem
  MenuIcon = StubNative::MenuIcon
  TrayIcon = StubNative::TrayIcon

  class Window < StubNative::Window
    include StubNative::WindowMenus
  end
end

# StubWindowMenusNative as Windows plays it: each window's menu bar also
# takes a theme (plan 042, phase 3).
module StubWindowsMenusNative
  StubWindowMenusNative.constants.each { |name| const_set(name, StubWindowMenusNative.const_get(name)) unless name == :Window }

  class Window < StubWindowMenusNative::Window
    include StubNative::WindowMenuThemes
  end
end
