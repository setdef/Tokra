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
  # Build from any thread, at any time once App#run has started, the
  # setup hook included. On the main thread the window exists when #build
  # returns. From another thread #build returns at once and the main
  # thread makes the window when its event loop gets to it; every call you
  # make on the window after #build waits behind that, so the window is
  # there for it.
  #
  # Mirrors Tauri's WebviewWindowBuilder (webview_window.rs:52-111,
  # 445-448). Tauri's rustdoc warns that on Windows building a window
  # inside a synchronous command deadlocks; Tokra's commands run outside
  # WebView2's callbacks, so they do not (plan 052, decision 5).
  #
  # === Examples
  #
  #   Tokra::Builder.default.setup do |app|
  #     Tokra::WebviewWindowBuilder.new(app, "settings", Tokra::WebviewUrl::App.new("settings.html"))
  #       .title("Settings")
  #       .inner_size(480, 360)
  #       .build
  #   end
  #
  #   Thread.new do
  #     report = Tokra::WebviewWindowBuilder.new(handle, "report", Tokra::WebviewUrl::App.new("report.html")).build
  #     report.set_title("Report ready")
  #   end
  class WebviewWindowBuilder
    # The title a window has when you set none: Tauri's default,
    # "Tauri App", named for Tokra (tauri-runtime-wry lib.rs:812-835).
    DEFAULT_TITLE = "Tokra"

    # Starts a builder for the window labeled +label+, whose webview opens
    # +url+, a WebviewUrl, in the app +manager+ belongs to: an App,
    # AppHandle, Window, Webview, or WebviewWindow.
    #
    # A label holds only letters, digits, <tt>-</tt>, <tt>/</tt>,
    # <tt>:</tt>, and <tt>_</tt>; #build checks it. Anything but a String
    # raises TypeError here.
    #
    # Mirrors Tauri's WebviewWindowBuilder::new (webview_window.rs:105-111).
    #
    # === Example
    #
    #   Tokra::WebviewWindowBuilder.new(app, "about", Tokra::WebviewUrl::App.new("about.html"))
    def initialize(manager, label, url)
      raise TypeError, "wrong argument type #{label.class} (expected String)" unless label.is_a?(String)

      @manager = manager
      @label = label
      @url = url
      @title = DEFAULT_TITLE
      @inner_size = nil
    end

    # Sets the window's title, and returns the builder.
    #
    # Mirrors Tauri's WebviewWindowBuilder::title (webview_window.rs:581-584,
    # window/mod.rs:561-566).
    #
    # === Example
    #
    #   builder.title("Settings")
    def title(title)
      raise TypeError, "wrong argument type #{title.class} (expected String)" unless title.is_a?(String)

      @title = title
      self
    end

    # Sets the window's inner size, in logical pixels, and returns the
    # builder. Without it the platform picks a size.
    #
    # Mirrors Tauri's WebviewWindowBuilder::inner_size
    # (webview_window.rs:477-480, window/mod.rs:455-460).
    #
    # === Example
    #
    #   builder.inner_size(480, 360)
    def inner_size(width, height)
      @inner_size = [Float(width), Float(height)]
      self
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

      menu = window_menu(handle)
      native_window, native_webview = handle.runtime_context.create_window(@label, title: @title,
        inner_size: @inner_size, url:, initialization_scripts: scripts, menu: menu&.menu)
      window = WindowManager.attach_window(Window.new(label: @label, native: native_window, app_handle: handle, menu:))
      webview = webviews.attach_webview(Webview.new(label: @label, native: native_webview, window:, app_handle: handle))
      manager = handle.manager
      label = @label
      window.run_on_main_thread do
        manager.emit(Event::EmitArgs.serialize(WindowManager::WINDOW_CREATED_EVENT, { "label" => label }))
      end
      WebviewWindow.new(window:, webview:)
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

    # The window's menu: the app's, if it has one, as Tauri's builder
    # gives a window with no menu of its own, and kept in the menus stash
    # (window/mod.rs:364-375, manager/menu.rs:54-65).
    private def window_menu(handle)
      menu = handle.menu
      return nil unless menu

      handle.menu_manager.insert_menu_into_stash(menu)
      Window::WindowMenu.new(is_app_wide: true, menu:)
    end
  end
end

# SPDX-SnippetEnd
