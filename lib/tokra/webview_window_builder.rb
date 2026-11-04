# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WebviewWindowBuilder adapted from tauri/crates/tauri/src/webview/webview_window.rs,
#                      window/mod.rs, manager/window.rs, manager/webview.rs, and
#                      tauri-runtime/src/window.rs

module Tokra
  # Makes a new window holding one webview: a WebviewWindow.
  #
  # Your app opens the windows its config lists. A settings pane, a
  # document, or a log viewer each wants a window of its own, opened when
  # the person asks for it, sometimes from a command and sometimes from a
  # thread that has finished some work.
  #
  # Name the window with a label, say what page it opens with a
  # WebviewUrl, set what you like, and call #build. The label names the
  # window and its webview from then on: Manager#get_webview_window finds
  # it, and its events carry it.
  #
  # Each setting is a method that answers the builder, so they chain:
  # the window's size and its limits, where it opens, its frame and
  # buttons, its menu, its theme and colors, and how it stacks with your
  # other windows; and for its webview, the scripts every page runs
  # first, the user agent, the proxy, private browsing, JavaScript, and
  # how drops and the clipboard reach the page. A few exist only on the
  # platform that has them: #title_bar_style, #hidden_title,
  # #tabbing_identifier, #traffic_light_position, and #allow_link_preview
  # on macOS; #owner and #drag_and_drop on Windows; #transient_for on
  # Linux; and #transparent everywhere but macOS. Ask with
  # <tt>respond_to?</tt>.
  #
  # Build from any thread, at any time once App#run has started, the
  # setup hook included. On the main thread the window exists when #build
  # returns. From another thread #build returns at once and the main
  # thread makes the window when its event loop gets to it; every call you
  # make on the window after #build waits behind that, so the window is
  # there for it.
  #
  # Mirrors Tauri's WebviewWindowBuilder (webview_window.rs:52-111,
  # 445-1231), which holds a WindowBuilder for the window's rows
  # (window/mod.rs:429-906) and a WebviewBuilder for the webview's
  # (webview/mod.rs:816-1203). Tauri's rustdoc warns that on Windows
  # building a window inside a synchronous command deadlocks; Tokra's
  # commands run outside WebView2's callbacks, so they do not (plan 052,
  # decision 5).
  #
  # === Examples
  #
  #   Tokra::Builder.default.setup do |app|
  #     Tokra::WebviewWindowBuilder.new(app, "settings", Tokra::WebviewUrl::App.new("settings.html"))
  #       .title("Settings")
  #       .inner_size(480, 360)
  #       .resizable(false)
  #       .center
  #       .build
  #   end
  #
  #   Thread.new do
  #     report = Tokra::WebviewWindowBuilder.new(handle, "report", Tokra::WebviewUrl::App.new("report.html")).build
  #     report.set_title("Report ready")
  #   end
  class WebviewWindowBuilder
    # The title a window has when you set none: Tauri's default,
    # "Tauri App", named for Tokra (tauri-runtime-wry lib.rs:813-835).
    DEFAULT_TITLE = WindowBuilder::DEFAULT_TITLE

    # Starts a builder for the window labeled +label+, whose webview opens
    # +url+, a WebviewUrl, in the app +manager+ belongs to: an App,
    # AppHandle, Window, Webview, or WebviewWindow.
    #
    # A label holds only letters, digits, <tt>-</tt>, <tt>/</tt>,
    # <tt>:</tt>, and <tt>_</tt>; #build checks it. Anything but a String
    # raises TypeError here.
    #
    # The window starts as Tauri's does: titled "Tokra", focused, and on
    # macOS with the Visible title bar over a content view that fills the
    # window, which keeps the devtools from pushing the page out of it.
    #
    # Mirrors Tauri's WebviewWindowBuilder::new (webview_window.rs:105-111)
    # and WindowBuilder::new's defaults (tauri-runtime-wry lib.rs:813-835).
    #
    # === Example
    #
    #   Tokra::WebviewWindowBuilder.new(app, "about", Tokra::WebviewUrl::App.new("about.html"))
    def initialize(manager, label, url)
      @window_builder = WindowBuilder.new(manager, label)
      @webview_builder = WebviewBuilder.new(label, url)
      @manager = manager
      @label = label
    end

    # Gives the window +menu+, a Menu, as its own, and returns the builder.
    #
    # Without one, the window takes the app's menu, if the app has one, on
    # Windows and Linux; on macOS menus belong to the app. On Windows the
    # menu bar takes the window's #theme.
    #
    # Mirrors Tauri's WebviewWindowBuilder::menu (webview_window.rs:456-459,
    # window/mod.rs:434-437, 357-381).
    #
    # === Example
    #
    #   builder.menu(Tokra::Menu::MenuBuilder.new(app).text("save", "Save").build)
    def menu(menu)
      forward { |rows| rows.menu(menu) }
    end

    # Calls the block with the window and each Menu::MenuEvent, and returns
    # the builder.
    #
    # The block hears a click on any menu, whether this window's, another
    # window's, or a tray icon's, and stops hearing once the window
    # closes. It becomes the window's Window#on_menu_event block once the
    # window joins the app.
    #
    # Mirrors Tauri's WebviewWindowBuilder::on_menu_event
    # (webview_window.rs:195-201, window/mod.rs:316-322, 404-407).
    #
    # === Example
    #
    #   builder.on_menu_event { |window, event| window.close if event.id == "close" }
    def on_menu_event(&)
      @window_builder.on_menu_event(&)
      self
    end

    # Opens the window in the middle of its monitor's work area, the part
    # the menu bar, the Dock, or the taskbar leave free, and returns the
    # builder.
    #
    # The monitor is the one holding #position, if you set one, or the
    # primary monitor. The size centered is the window's #inner_size, or
    # 800 by 600 without one, held within its limits; on Windows a
    # decorated window counts its frame.
    #
    # Mirrors Tauri's WebviewWindowBuilder::center (webview_window.rs:463-466),
    # whose runtime centers it as it builds the window (tauri-runtime-wry
    # lib.rs:950-953, 4359-4436).
    #
    # === Example
    #
    #   builder.inner_size(480, 360).center
    def center
      forward(&:center)
    end

    # Opens the window with its top-left corner at +x+, +y+, in logical
    # pixels from the top-left of the desktop, and returns the builder.
    # Anything but a number raises TypeError or ArgumentError here.
    #
    # Mirrors Tauri's WebviewWindowBuilder::position (webview_window.rs:470-473,
    # tauri-runtime-wry lib.rs:955-958).
    #
    # === Example
    #
    #   builder.position(100, 80)
    def position(x, y)
      forward { |rows| rows.position(x, y) }
    end

    # Sets the window's inner size, in logical pixels, and returns the
    # builder. Without it the platform picks a size. On macOS, with the
    # default Visible title bar, the size includes the title bar, which lies
    # over the top of the page, so the page's own height is about 32 points
    # less; #title_bar_style Transparent puts the page below it instead.
    #
    # Mirrors Tauri's WebviewWindowBuilder::inner_size
    # (webview_window.rs:477-480, window/mod.rs:455-460).
    #
    # === Example
    #
    #   builder.inner_size(480, 360)
    def inner_size(width, height)
      forward { |rows| rows.inner_size(width, height) }
    end

    # Keeps the window's inner size at least +min_width+ by +min_height+,
    # in logical pixels, and returns the builder. It sets the minimums of
    # the window's limits and leaves the maximums.
    #
    # Mirrors Tauri's WebviewWindowBuilder::min_inner_size
    # (webview_window.rs:484-487, tauri-runtime-wry lib.rs:967-972).
    #
    # === Example
    #
    #   builder.min_inner_size(400, 300)
    def min_inner_size(min_width, min_height)
      forward { |rows| rows.min_inner_size(min_width, min_height) }
    end

    # Keeps the window's inner size at most +max_width+ by +max_height+,
    # in logical pixels, and returns the builder. It sets the maximums of
    # the window's limits and leaves the minimums.
    #
    # Mirrors Tauri's WebviewWindowBuilder::max_inner_size
    # (webview_window.rs:491-494, tauri-runtime-wry lib.rs:974-979).
    #
    # === Example
    #
    #   builder.max_inner_size(1600, 1200)
    def max_inner_size(max_width, max_height)
      forward { |rows| rows.max_inner_size(max_width, max_height) }
    end

    # Sets all four of the window's size limits from +constraints+, a
    # WindowSizeConstraints, and returns the builder. It replaces whatever
    # #min_inner_size and #max_inner_size set before it.
    #
    # Mirrors Tauri's WebviewWindowBuilder::inner_size_constraints
    # (webview_window.rs:498-504, tauri-runtime-wry lib.rs:981-989).
    #
    # === Example
    #
    #   builder.inner_size_constraints(Tokra::WindowSizeConstraints.new(min_width: Tokra::LogicalUnit.new(400)))
    def inner_size_constraints(constraints)
      forward { |rows| rows.inner_size_constraints(constraints) }
    end

    # Shrinks the window, as it opens, to fit its monitor's work area, and
    # returns the builder.
    #
    # The check runs only when the window is built; resizing it later can
    # still make it overflow.
    #
    # Mirrors Tauri's WebviewWindowBuilder::prevent_overflow
    # (webview_window.rs:515-518, tauri-runtime-wry lib.rs:996-1001,
    # 4406-4428).
    #
    # === Example
    #
    #   builder.inner_size(4000, 3000).prevent_overflow
    def prevent_overflow
      forward(&:prevent_overflow)
    end

    # Shrinks the window, as it opens, to fit its monitor's work area less
    # +margin+, a LogicalSize or a PhysicalSize, and returns the builder.
    # The check runs only when the window is built. A margin wider than the
    # work area leaves no room, and the window is as small as the platform
    # allows; Tauri's subtraction would wrap or panic there.
    #
    # Mirrors Tauri's WebviewWindowBuilder::prevent_overflow_with_margin
    # (webview_window.rs:529-533, tauri-runtime-wry lib.rs:1009-1012,
    # 4406-4428).
    #
    # === Example
    #
    #   builder.prevent_overflow_with_margin(Tokra::LogicalSize.new(width: 40, height: 40))
    def prevent_overflow_with_margin(margin)
      forward { |rows| rows.prevent_overflow_with_margin(margin) }
    end

    # Lets a person resize the window, or not, and returns the builder. A
    # window that does not resize turns off its maximize button too.
    #
    # Mirrors Tauri's WebviewWindowBuilder::resizable (webview_window.rs:537-540).
    #
    # === Example
    #
    #   builder.resizable(false)
    def resizable(resizable)
      forward { |rows| rows.resizable(resizable) }
    end

    # Turns the window's maximize button on or off, and returns the
    # builder. A window that does not resize ignores it. On macOS it is the
    # zoom button, which also enters full screen; Linux has no such
    # setting.
    #
    # Mirrors Tauri's WebviewWindowBuilder::maximizable (webview_window.rs:550-553).
    #
    # === Example
    #
    #   builder.maximizable(false)
    def maximizable(maximizable)
      forward { |rows| rows.maximizable(maximizable) }
    end

    # Turns the window's minimize button on or off, and returns the
    # builder. Linux has no such setting.
    #
    # Mirrors Tauri's WebviewWindowBuilder::minimizable (webview_window.rs:561-564).
    #
    # === Example
    #
    #   builder.minimizable(false)
    def minimizable(minimizable)
      forward { |rows| rows.minimizable(minimizable) }
    end

    # Turns the window's close button on or off, and returns the builder.
    # On Linux GTK asks the window manager to hide the button, which it
    # may not do.
    #
    # Mirrors Tauri's WebviewWindowBuilder::closable (webview_window.rs:574-577).
    #
    # === Example
    #
    #   builder.closable(false)
    def closable(closable)
      forward { |rows| rows.closable(closable) }
    end

    # Sets the window's title, and returns the builder. Anything but a
    # String raises TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::title (webview_window.rs:581-584,
    # window/mod.rs:561-566).
    #
    # === Example
    #
    #   builder.title("Settings")
    def title(title)
      forward { |rows| rows.title(title) }
    end

    # Opens the window full screen, without a frame, on its monitor, or
    # not, and returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::fullscreen (webview_window.rs:588-591),
    # which asks tao for borderless full screen (tauri-runtime-wry
    # lib.rs:1039-1048).
    #
    # === Example
    #
    #   builder.fullscreen(true)
    def fullscreen(fullscreen)
      forward { |rows| rows.fullscreen(fullscreen) }
    end

    # Focuses the window and its webview when they open, and returns the
    # builder. Deprecated, as in Tauri: a window is focused by default,
    # and #focused says whether. With Ruby's deprecation warnings on, it
    # warns with Tauri's note.
    #
    # Mirrors Tauri's deprecated WebviewWindowBuilder::focus
    # (webview_window.rs:595-604).
    #
    # === Example
    #
    #   builder.focused(true)
    def focus
      WindowBuilder.warn_focus_deprecated(self.class)
      @window_builder.focused(true)
      webview_row { |rows| rows.focused(true) }
    end

    # Lets the window take focus, or not, and returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::focusable (webview_window.rs:607-610).
    #
    # === Example
    #
    #   builder.focusable(false)
    def focusable(focusable)
      forward { |rows| rows.focusable(focusable) }
    end

    # Focuses the window and its webview when they open, or not, and
    # returns the builder. They are focused unless you say otherwise.
    #
    # Mirrors Tauri's WebviewWindowBuilder::focused (webview_window.rs:614-618),
    # which sets both the window's and the webview's.
    #
    # === Example
    #
    #   builder.focused(false)
    def focused(focused)
      @window_builder.focused(focused)
      webview_row { |rows| rows.focused(focused) }
    end

    # Opens the window maximized, or not, and returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::maximized (webview_window.rs:622-625).
    #
    # === Example
    #
    #   builder.maximized(true)
    def maximized(maximized)
      forward { |rows| rows.maximized(maximized) }
    end

    # Shows the window as soon as it opens, or keeps it hidden until
    # Window#show, and returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::visible (webview_window.rs:629-632).
    #
    # === Example
    #
    #   builder.visible(false)
    def visible(visible)
      forward { |rows| rows.visible(visible) }
    end

    # Draws the window in +theme+, a Theme, or in the system's for +nil+,
    # and returns the builder. On Windows the menu bar and the webview
    # follow it.
    #
    # Mirrors Tauri's WebviewWindowBuilder::theme (webview_window.rs:640-643,
    # tauri-runtime-wry lib.rs:1227-1238, 4877-4881).
    #
    # === Example
    #
    #   builder.theme(Tokra::Theme::Dark)
    def theme(theme)
      forward { |rows| rows.theme(theme) }
    end

    # Gives the window its frame, title bar, and buttons, or takes them
    # away, and returns the builder. On Windows and Linux a person can
    # still resize an undecorated window by its edges.
    #
    # Mirrors Tauri's WebviewWindowBuilder::decorations (webview_window.rs:647-650).
    #
    # === Example
    #
    #   builder.decorations(false)
    def decorations(decorations)
      forward { |rows| rows.decorations(decorations) }
    end

    # Keeps the window below every other, or not, and returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::always_on_bottom
    # (webview_window.rs:654-657).
    #
    # === Example
    #
    #   builder.always_on_bottom(true)
    def always_on_bottom(always_on_bottom)
      forward { |rows| rows.always_on_bottom(always_on_bottom) }
    end

    # Keeps the window above every other, or not, and returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::always_on_top (webview_window.rs:661-664).
    #
    # === Example
    #
    #   builder.always_on_top(true)
    def always_on_top(always_on_top)
      forward { |rows| rows.always_on_top(always_on_top) }
    end

    # Shows the window on every workspace or virtual desktop, or not, and
    # returns the builder. Windows has no such setting.
    #
    # Mirrors Tauri's WebviewWindowBuilder::visible_on_all_workspaces
    # (webview_window.rs:668-673).
    #
    # === Example
    #
    #   builder.visible_on_all_workspaces(true)
    def visible_on_all_workspaces(visible_on_all_workspaces)
      forward { |rows| rows.visible_on_all_workspaces(visible_on_all_workspaces) }
    end

    # Keeps other apps from capturing the window's contents, or not, and
    # returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::content_protected
    # (webview_window.rs:677-680).
    #
    # === Example
    #
    #   builder.content_protected(true)
    def content_protected(protected)
      forward { |rows| rows.content_protected(protected) }
    end

    # Gives the window +icon+, a Tokra::Image, and returns the builder.
    # macOS has no window icons.
    #
    # The image becomes an icon here, as Window#set_icon makes one, so an
    # image whose pixels do not fill its width and height raises
    # Error::Runtime "invalid icon: ..." at once. Anything but an Image
    # raises TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::icon (webview_window.rs:683-686,
    # tauri-runtime-wry lib.rs:1197-1202).
    #
    # === Example
    #
    #   builder.icon(Tokra::Image.from_path("icons/32x32.png"))
    def icon(icon)
      forward { |rows| rows.icon(icon) }
    end

    # Hides the window from the taskbar, or not, and returns the builder.
    # macOS has no taskbar, so there it does nothing.
    #
    # Mirrors Tauri's WebviewWindowBuilder::skip_taskbar
    # (webview_window.rs:694-697, tauri-runtime-wry lib.rs:1209-1225).
    #
    # === Example
    #
    #   builder.skip_taskbar(true)
    def skip_taskbar(skip)
      forward { |rows| rows.skip_taskbar(skip) }
    end

    # Names the Windows window class the window registers, and returns
    # the builder. Without it the class is "Tokra Window", as Tauri's is
    # "Tauri Window". Other platforms ignore it. Anything but a String
    # raises TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::window_classname
    # (webview_window.rs:701-704, tauri-runtime-wry lib.rs:829-832,
    # 1251-1259).
    #
    # === Example
    #
    #   builder.window_classname("Notes Window")
    def window_classname(classname)
      forward { |rows| rows.window_classname(classname) }
    end

    # Gives the window a shadow, or takes it away, and returns the builder.
    #
    # On macOS it is AppKit's window shadow. On Windows it matters only for
    # an undecorated window: +true+ draws a thin border and, on Windows 11,
    # rounded corners; a decorated window always has its shadow. Linux has
    # no such setting.
    #
    # Mirrors Tauri's WebviewWindowBuilder::shadow (webview_window.rs:716-719,
    # tauri-runtime-wry lib.rs:1103-1113).
    #
    # === Example
    #
    #   builder.decorations(false).shadow(true)
    def shadow(enable)
      forward { |rows| rows.shadow(enable) }
    end

    # Opens the window as a child of +parent+, a WebviewWindow, and
    # returns the builder.
    #
    # Each platform has its own kind of child. On Windows +parent+ owns
    # the window: it stays above +parent+, hides when +parent+ is
    # minimized, and closes with it. On Linux the window is transient for
    # +parent+, as a dialog is. On macOS it is an AppKit child window,
    # which moves with +parent+.
    #
    # It asks for +parent+'s native window at once, waiting for the main
    # thread, and raises Error::Runtime "failed to receive message from
    # webview" if +parent+ is closed. Anything but a WebviewWindow raises
    # TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::parent (webview_window.rs:732-735,
    # window/mod.rs:727-758).
    #
    # === Example
    #
    #   builder.parent(app.get_webview_window("main"))
    def parent(parent)
      @window_builder.parent(webview_window(parent).window)
      self
    end

    # Applies +effects+, a WindowEffectsConfig, as the window opens, as
    # Window#set_effects does, and returns the builder. The window's own
    # background must be transparent for an effect to show, and Linux has
    # none. An effect the platform refuses is dropped, as Tauri drops it.
    #
    # Mirrors Tauri's WebviewWindowBuilder::effects (webview_window.rs:893-896),
    # applied in the main-thread task that follows the window's creation
    # (window/mod.rs:411-424).
    #
    # === Example
    #
    #   builder.effects(Tokra::EffectsBuilder.new.effect(Tokra::Effect::Mica).build)
    def effects(effects)
      forward { |rows| rows.effects(effects) }
    end

    # Colors the window and its webview with +color+, a Tokra::Color, and
    # returns the builder. Anything else raises TypeError.
    #
    # On Windows the window ignores the alpha, and the webview treats any
    # alpha but 0 as 255. macOS does not color the webview.
    #
    # Mirrors Tauri's WebviewWindowBuilder::background_color
    # (webview_window.rs:1170-1185), which sets both.
    #
    # === Example
    #
    #   builder.background_color(Tokra::Color.from_str("#1e1e1e"))
    def background_color(color)
      @window_builder.background_color(color)
      webview_row { |rows| rows.background_color(color) }
    end

    # Lets a click on the window, while another app is in front, reach the
    # page as well as bring the window forward, and returns the builder.
    # Off by default, so the first click only activates the window. Only
    # macOS has the choice.
    #
    # Mirrors Tauri's WebviewWindowBuilder::accept_first_mouse
    # (webview_window.rs:903-906; tauri-runtime-wry lib.rs:4628).
    #
    # === Example
    #
    #   builder.accept_first_mouse(true)
    def accept_first_mouse(accept)
      webview_row { |rows| rows.accept_first_mouse(accept) }
    end

    # Runs +script+, a String of JavaScript, in every page the webview
    # loads, and returns the builder.
    #
    # It runs once the page's global object exists, before the HTML is
    # parsed and before any script of the page's own, and only in the main
    # frame; on Windows it runs in every frame. Tokra's own scripts, and
    # each plugin's, run first, and yours in the order you add them. It
    # runs on every top-level navigation, so check
    # <tt>window.location</tt> if it should run only for your own pages.
    # Anything but a String raises TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::initialization_script
    # (webview_window.rs:946-949, webview/mod.rs:873-882), whose scripts
    # follow Tauri's own (manager/webview.rs:152-218).
    #
    # === Example
    #
    #   builder.initialization_script(<<~JS)
    #     if (window.location.origin === "tokra://localhost") window.__MY_FLAG__ = true
    #   JS
    def initialization_script(script)
      webview_row { |rows| rows.initialization_script(script) }
    end

    # Runs +script+ in every frame of every page the webview loads, the
    # main frame and each iframe, and returns the builder. It runs where
    # and when #initialization_script does, in the same order as the
    # scripts you add with it. Check <tt>window.location</tt> to keep it
    # off frames you do not own.
    #
    # Mirrors Tauri's WebviewWindowBuilder::initialization_script_for_all_frames
    # (webview_window.rs:988-994, webview/mod.rs:932-941).
    #
    # === Example
    #
    #   builder.initialization_script_for_all_frames("window.__IN_APP__ = true")
    def initialization_script_for_all_frames(script)
      webview_row { |rows| rows.initialization_script_for_all_frames(script) }
    end

    # Has the webview send +user_agent+, a String, as its User-Agent, in
    # place of the platform's, and returns the builder. The page reads it
    # as <tt>navigator.userAgent</tt>. Anything but a String raises
    # TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::user_agent (webview_window.rs:997-1000;
    # tauri-runtime-wry lib.rs:4857-4859).
    #
    # === Example
    #
    #   builder.user_agent("MyApp/1.0")
    def user_agent(user_agent)
      webview_row { |rows| rows.user_agent(user_agent) }
    end

    # Starts WebView2 with +additional_args+, a String of Chromium
    # switches, and returns the builder. Only Windows reads it.
    #
    # WebView2 already starts with
    # <tt>--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection</tt>,
    # and your String replaces that, so repeat those switches if you want
    # them kept, and WebView2's
    # <tt>--autoplay-policy=no-user-gesture-required</tt>. wry turns
    # #proxy_url into a <tt>--proxy-server</tt> switch only when you give
    # no switches of your own, so with this row the proxy is dropped
    # without a word; add <tt>--proxy-server</tt> here yourself (wry
    # webview2/mod.rs:294-323). Webviews that share a data directory share
    # one browser process, which takes the switches of the first webview
    # made in it; a later webview that asks for other switches can fail to
    # open.
    #
    # Mirrors Tauri's WebviewWindowBuilder::additional_browser_args
    # (webview_window.rs:1013-1018; tauri-runtime-wry lib.rs:4868-4871).
    #
    # === Example
    #
    #   builder.additional_browser_args("--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --disable-gpu")
    def additional_browser_args(additional_args)
      webview_row { |rows| rows.additional_browser_args(additional_args) }
    end

    # Hands files dragged onto the page to the page, as a browser does,
    # and returns the builder.
    #
    # By default Tokra takes each drag and drop itself, and the window
    # hears it as WindowEvent::DragDrop, with the paths, while the page
    # sees none of it. On Windows a page that uses HTML5 drag and drop
    # needs this row; on every platform the window then hears no drops.
    #
    # Mirrors Tauri's WebviewWindowBuilder::disable_drag_drop_handler
    # (webview_window.rs:1029-1032; tauri-runtime-wry lib.rs:4669).
    #
    # === Example
    #
    #   builder.disable_drag_drop_handler
    def disable_drag_drop_handler
      webview_row(&:disable_drag_drop_handler)
    end

    # Lets the page read and write the clipboard, on Linux and Windows,
    # and returns the builder. macOS always lets it; there the page's
    # copy and paste shortcuts still come from your app menu's
    # accelerators.
    #
    # Mirrors Tauri's WebviewWindowBuilder::enable_clipboard_access
    # (webview_window.rs:1039-1042; tauri-runtime-wry lib.rs:4630).
    #
    # === Example
    #
    #   builder.enable_clipboard_access
    def enable_clipboard_access
      webview_row(&:enable_clipboard_access)
    end

    # Opens the webview in private browsing, which keeps no cookies,
    # storage, or cache once it closes, or not, and returns the builder.
    #
    # On macOS the webview gets a data store of its own that lives only
    # in memory. On Windows it needs the WebView2 Runtime 101.0.1210.39 or
    # newer, and does nothing on an older one.
    #
    # Mirrors Tauri's WebviewWindowBuilder::incognito (webview_window.rs:1050-1053;
    # tauri-runtime-wry lib.rs:4629).
    #
    # === Example
    #
    #   builder.incognito(true)
    def incognito(incognito)
      webview_row { |rows| rows.incognito(incognito) }
    end

    # Sends every request the webview makes through the proxy at +url+, a
    # Ferro::Url::Url, and returns the builder. Anything else, a Ruby URI
    # included, raises TypeError.
    #
    # The URL is <tt>http://</tt>, for an HTTP CONNECT proxy, or
    # <tt>socks5://</tt>, for a SOCKSv5 proxy, with the proxy's host and
    # port. With any other scheme the webview fails to open: the window
    # is dropped and the failure is warned on $stderr as "Invalid proxy
    # url", not raised, as Tauri logs it. The window and webview stay in
    # the app and answer as closed ones do, as any failed window does.
    #
    # On Windows the proxy becomes a WebView2 <tt>--proxy-server</tt>
    # switch, which wry adds only when #additional_browser_args gives none
    # of its own; with that row the proxy is dropped without a word, so
    # put the switch there yourself (wry webview2/mod.rs:294-323).
    #
    # macOS ignores the proxy. Tauri reads it there only with its
    # macos-proxy feature, which needs macOS 14, and Tokra does not build
    # that feature in (plan 052, question 3).
    #
    # Mirrors Tauri's WebviewWindowBuilder::proxy_url (webview_window.rs:1066-1069)
    # and tauri-runtime-wry's parse_proxy_url (lib.rs:4301-4316, 4861-4865).
    #
    # === Example
    #
    #   builder.proxy_url(Ferro::Url::Url.parse("socks5://127.0.0.1:1080"))
    def proxy_url(url)
      webview_row { |rows| rows.proxy_url(url) }
    end

    # Lets the person install browser extensions in the webview, or not,
    # and returns the builder. Only WebView2 on Windows has them; see
    # #extensions_path.
    #
    # Mirrors Tauri's WebviewWindowBuilder::browser_extensions_enabled
    # (webview_window.rs:1110-1113; tauri-runtime-wry lib.rs:4892-4895).
    #
    # === Example
    #
    #   builder.browser_extensions_enabled(true)
    def browser_extensions_enabled(enabled)
      webview_row { |rows| rows.browser_extensions_enabled(enabled) }
    end

    # Loads the extensions in the directory +path+, a String or a
    # Pathname, and returns the builder.
    #
    # On Windows the directory holds unpacked Chrome extensions, which
    # load once #browser_extensions_enabled is on. On Linux it holds
    # compiled WebKitGTK web extensions, <tt>.so</tt> files. macOS ignores
    # it. Anything that is not a path raises TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::extensions_path
    # (webview_window.rs:1122-1125; tauri-runtime-wry lib.rs:4897-4909).
    #
    # === Example
    #
    #   builder.browser_extensions_enabled(true).extensions_path(Pathname("extensions"))
    def extensions_path(path)
      webview_row { |rows| rows.extensions_path(path) }
    end

    # Keeps the webview's cookies, storage, and cache in the data store
    # named +data_store_identifier+, 16 Integers from 0 to 255 that make a
    # UUID, and returns the builder.
    #
    # Webviews with one identifier share their data, and webviews with
    # different ones keep theirs apart, as a data directory does
    # elsewhere. Only macOS 14 and newer have such stores; older macOS
    # and the other platforms use the default one. With #incognito the
    # webview keeps its data in memory instead. Anything but an Array of
    # Integers raises TypeError, and a wrong count or a byte out of range
    # ArgumentError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::data_store_identifier
    # (webview_window.rs:1133-1138; tauri-runtime-wry lib.rs:4925-4928),
    # whose Rust <tt>[u8; 16]</tt> is 16 Integers, as the config's array
    # of 16 numbers is.
    #
    # === Example
    #
    #   builder.data_store_identifier(SecureRandom.uuid.delete("-").scan(/../).map(&:hex))
    def data_store_identifier(data_store_identifier)
      webview_row { |rows| rows.data_store_identifier(data_store_identifier) }
    end

    # Chooses how the page runs while nobody can see it, with +policy+, a
    # BackgroundThrottlingPolicy, and returns the builder.
    #
    # By default a hidden or minimized page runs its timers slower, and
    # after about five minutes it stops until it is in sight again. Only
    # macOS 14 and newer take a policy; Linux and Windows keep their own,
    # where a pending Web Lock may keep a page running. Anything but a
    # BackgroundThrottlingPolicy raises TypeError.
    #
    # Mirrors Tauri's WebviewWindowBuilder::background_throttling
    # (webview_window.rs:1202-1205; tauri-runtime-wry lib.rs:4647-4659).
    #
    # === Example
    #
    #   builder.background_throttling(Tokra::BackgroundThrottlingPolicy::Disabled)
    def background_throttling(policy)
      webview_row { |rows| rows.background_throttling(policy) }
    end

    # Turns off the page's JavaScript, and returns the builder. The page's
    # own scripts never run, so it cannot call your commands, and its
    # <tt>noscript</tt> elements show instead.
    #
    # Mirrors Tauri's WebviewWindowBuilder::disable_javascript
    # (webview_window.rs:1209-1212; tauri-runtime-wry lib.rs:4661-4663).
    #
    # === Example
    #
    #   builder.disable_javascript
    def disable_javascript
      webview_row(&:disable_javascript)
    end

    # Draws the webview's scroll bars in +style+, a ScrollBarStyle, and
    # returns the builder. Anything else raises TypeError.
    #
    # Only Windows has a style but Default: ScrollBarStyle::FluentOverlay.
    # Give every webview that shares a data directory the same style. CSS
    # that styles the scroll bars applies on top.
    #
    # Mirrors Tauri's WebviewWindowBuilder::scroll_bar_style
    # (webview_window.rs:1228-1231; tauri-runtime-wry lib.rs:4883-4889).
    #
    # === Example
    #
    #   builder.scroll_bar_style(Tokra::ScrollBarStyle::Default)
    def scroll_bar_style(style)
      webview_row { |rows| rows.scroll_bar_style(style) }
    end

    # Makes the window and its webview, joins them to the app, and answers
    # the WebviewWindow.
    #
    # It checks the label first, the webview's before the window's, as
    # Tauri does:
    #
    # - A label with any character but a letter, a digit, <tt>-</tt>,
    #   <tt>/</tt>, <tt>:</tt>, or <tt>_</tt> raises Error::Runtime,
    #   "runtime error: Window labels must only include alphanumeric
    #   characters, \`-\`, \`/\`, \`:\` and \`_\`." Letters and digits are
    #   Unicode's, so <tt>"é"</tt> passes, and the empty label passes.
    #   Rust and Ruby follow different Unicode versions, so a character
    #   only the newer one has assigned is judged differently.
    # - A label a webview has raises Error::WebviewLabelAlreadyExists, and
    #   one a window has, Error::WindowLabelAlreadyExists.
    #
    # Then the app has the window: plugins hear Plugin#window_created and
    # then Plugin#webview_created, on the main thread; every listener
    # hears <tt>tauri://webview-created</tt> and then
    # <tt>tauri://window-created</tt>, each with <tt>{"label": label}</tt>.
    # The #on_menu_event block becomes the window's, and the #effects
    # apply just before <tt>tauri://window-created</tt>.
    #
    # If the platform refuses to make the window, the failure is warned on
    # $stderr, not raised, as Tauri logs it: "failed to create window", or
    # "failed to create webview: ..." with the platform's reason. The
    # window and webview stay in the app, and answer as closed ones do; the
    # app does not wait for them to close before it exits. They keep their
    # label for as long as the app runs, so building that label again
    # raises Error::WebviewLabelAlreadyExists, as in Tauri. Before App#run
    # there is no event loop to make a window in, and this raises
    # Error::Runtime.
    #
    # A WebviewUrl::App path the url crate cannot join to the app URL, one
    # naming another host such as <tt>//exa mple</tt>, raises
    # Error::InvalidUrl with the crate's reason, before anything is built.
    # *Deviation*: Tauri unwraps that error, so its app panics
    # (manager/webview.rs:423-427); a panic would end Ruby's VM.
    #
    # Two threads that build one label at the same moment can both pass
    # the check, as in Tauri, whose check and insert are separate too. In
    # Tokra the second native window then also takes the first's events,
    # which the native layer routes by label; keep labels unique.
    #
    # Mirrors Tauri's WebviewWindowBuilder::build (webview_window.rs:445-448),
    # WindowBuilder#with_webview and build_internal (window/mod.rs:328-427),
    # and the checks of PendingWebview::new, prepare_webview,
    # PendingWindow::new, and prepare_window (tauri-runtime window.rs:494-522,
    # webview.rs:230-255; manager/webview.rs:401-409; manager/window.rs:61-77).
    #
    # === Example
    #
    #   window = builder.build
    #   window.label  #=> "settings"
    def build
      handle = @manager.app_handle
      webviews = handle.webview_manager
      # The webview first (window/mod.rs:333), then the window (:354, :361).
      check_label
      raise Error::WebviewLabelAlreadyExists, @label if handle.webviews.key?(@label)

      url = webviews.webview_url(@webview_builder.url)
      # Tauri's own scripts, each for the main frame, and then the
      # builder's (manager/webview.rs:152-218).
      scripts = webviews.initialization_scripts(@label, @label).map { |script| [script, true] } #: Array[[String, bool]]
      scripts.concat(@webview_builder.initialization_scripts)
      raise Error::WindowLabelAlreadyExists, @label if handle.windows.key?(@label)

      menu = @window_builder.window_menu(handle)
      native_window, native_webview = handle.runtime_context.create_window(@label,
        window_attributes: @window_builder.native_attributes, webview_attributes: @webview_builder.native_attributes,
        url:, initialization_scripts: scripts, menu: menu&.menu)
      window = WindowManager.attach_window(Window.new(label: @label, native: native_window, app_handle: handle, menu:))
      webview = webviews.attach_webview(Webview.new(label: @label, native: native_webview, window:, app_handle: handle))
      handler = @window_builder.menu_event_handler
      window.on_menu_event(&handler) if handler
      after_creation(handle, window)
      WebviewWindow.new(window:, webview:)
    end

    # The main-thread task Tauri runs once the window exists: its effects,
    # their error dropped, then <tt>tauri://window-created</tt>
    # (window/mod.rs:409-424).
    private def after_creation(handle, window)
      manager = handle.manager
      label = @label
      effects = @window_builder.window_effects
      window.run_on_main_thread do
        apply_effects(window, effects) if effects
        manager.emit(Event::EmitArgs.serialize(WindowManager::WINDOW_CREATED_EVENT, { "label" => label }))
      end
    end

    # Window#set_effects, whose failure Tauri's <tt>_ =</tt> drops.
    private def apply_effects(window, effects)
      window.set_effects(effects)
    rescue
      nil
    end

    # Hands the window builder to the block, which sets a row on it as
    # Tauri's rows forward theirs, and answers this builder.
    private def forward
      yield @window_builder
      self
    end

    # Hands the webview builder to the block, which sets a row on it as
    # Tauri's webview rows forward theirs, and answers this builder.
    private def webview_row
      yield @webview_builder
      self
    end

    # +value+, raising TypeError unless it is a WebviewWindow.
    private def webview_window(value)
      raise TypeError, "wrong argument type #{value.class} (expected Tokra::WebviewWindow)" unless value.is_a?(WebviewWindow)

      value
    end

    # Raises Error::Runtime unless every character of the label is one
    # Rust's char::is_alphanumeric accepts, or <tt>-</tt>, <tt>/</tt>,
    # <tt>:</tt>, <tt>_</tt> (tauri-runtime window.rs:494-498). Rust's
    # alphanumeric is Unicode's Alphabetic or any Numeric category. A
    # String whose encoding is invalid fails too, before the match, which
    # would raise on it.
    private def check_label
      valid = @label.valid_encoding? && @label.match?(%r{\A(?:\p{Alphabetic}|\p{N}|[-/:_])*\z})
      raise Error::Runtime, Error::Runtime::INVALID_WINDOW_LABEL unless valid
    end
  end
end

# SPDX-SnippetEnd
