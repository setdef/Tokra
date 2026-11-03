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
  # Your app opens with one window, +main+. A settings pane, a document,
  # or a log viewer each wants a window of its own, opened when the person
  # asks for it, sometimes from a command and sometimes from a thread
  # that has finished some work.
  #
  # Name the window with a label, say what page it opens with a
  # WebviewUrl, set what you like, and call #build. The label names the
  # window and its webview from then on: Manager#get_webview_window finds
  # it, and its events carry it.
  #
  # Each setting is a method that answers the builder, so they chain:
  # the window's size and its limits, where it opens, its frame and
  # buttons, its menu, its theme and colors, and how it stacks with your
  # other windows. A few exist only on the platform that has them:
  # #title_bar_style, #hidden_title, #tabbing_identifier, and
  # #traffic_light_position on macOS; #owner and #drag_and_drop on
  # Windows; #transient_for on Linux; and #transparent everywhere but
  # macOS. Ask with <tt>respond_to?</tt>.
  #
  # Build from any thread, at any time once App#run has started, the
  # setup hook included. On the main thread the window exists when #build
  # returns. From another thread #build returns at once and the main
  # thread makes the window when its event loop gets to it; every call you
  # make on the window after #build waits behind that, so the window is
  # there for it.
  #
  # Mirrors Tauri's WebviewWindowBuilder (webview_window.rs:52-111,
  # 445-897), which holds a WindowBuilder for the window's rows
  # (window/mod.rs:429-906) and sets the webview's own. Tauri's rustdoc
  # warns that on Windows building a window inside a synchronous command
  # deadlocks; Tokra's commands run outside WebView2's callbacks, so they
  # do not (plan 052, decision 5).
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
      @manager = manager
      @label = label
      @url = url
      @webview_attributes = {
        focused: true, transparent: false, background_color: nil, traffic_light_position: nil
      } #: Hash[Symbol, Native::WebView::attribute]
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
      webview(:focused, true)
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
      webview(:focused, focused ? true : false)
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
      webview(:background_color, [color.red, color.green, color.blue, color.alpha])
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

      url = webviews.webview_url(@url)
      scripts = webviews.initialization_scripts(@label, @label)
      raise Error::WindowLabelAlreadyExists, @label if handle.windows.key?(@label)

      menu = @window_builder.window_menu(handle)
      native_window, native_webview = handle.runtime_context.create_window(@label,
        window_attributes: @window_builder.native_attributes, webview_attributes: @webview_attributes.dup,
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

    # Records the webview attribute +key+ and answers this builder.
    private def webview(key, value)
      @webview_attributes[key] = value
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
