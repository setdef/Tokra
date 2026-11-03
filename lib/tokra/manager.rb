# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Manager's provided methods adapted from tauri/crates/tauri/src/lib.rs

module Tokra
  # The shared surface of every handle onto a running app.
  #
  # Your code holds different handles at different moments: the App in a
  # setup hook, an AppHandle in a plugin, a Window or Webview in an event
  # callback. Each one belongs to the same application, with one set of
  # managed state, one configuration, and one registry of windows and
  # webviews.
  #
  # Without a shared surface, you would need to know which handle you hold
  # before you could reach that state. Manager gives App, AppHandle,
  # Window, and Webview the same methods, all answering from the same app.
  #
  # Use it to manage and read state, read the configuration, or look up a
  # window or webview from whatever handle you have.
  #
  # An including class supplies +app_handle+ and +resources_table+; every
  # other method reaches the app through +app_handle+. This mirrors Tauri's
  # Manager trait (lib.rs), whose provided methods all go through the
  # shared AppManager, and whose implementors (App, AppHandle, Window,
  # Webview) define only resources_table.
  #
  # Plugins can extend Manager to add a method to every handle:
  #
  #   module ClipboardExt
  #     def clipboard
  #       state(Clipboard)
  #     end
  #   end
  #
  #   Tokra::Manager.include(ClipboardExt)
  #
  # === Examples
  #
  #   window.manage(Settings.new(theme: "dark"))
  #   app.state(Settings).theme     # => "dark"
  #   webview.get_window("main")    # => the main Window
  module Manager
    # The application handle associated with this manager. Each including
    # class supplies it.
    #
    # === Example
    #
    #   window.app_handle.emit("ready", {})
    def app_handle
      raise NotImplementedError, "#{self.class} must implement #app_handle"
    end

    # The Config the app was created with.
    #
    # === Example
    #
    #   webview.config.identifier
    def config
      app_handle.config
    end

    # Adds +state+ to the state the application manages.
    #
    # If state of the same class was managed before, the state is
    # unchanged and +false+ is returned. Otherwise +true+ is returned.
    # Retrieve it later with #state or #try_state from any handle.
    #
    # === Example
    #
    #   window.manage(Counter.new) # => true
    def manage(state)
      app_handle.manage(state)
    end

    # The managed state of class +klass+.
    #
    # Raises KeyError if no state of that class was managed (Tauri panics
    # here). Use #try_state when the state may be missing.
    #
    # === Example
    #
    #   webview.state(Counter)
    def state(klass)
      app_handle.state(klass)
    end

    # The managed state of class +klass+, or +nil+ if none was managed.
    #
    # === Example
    #
    #   app.try_state(Counter) # => nil before manage
    def try_state(klass)
      app_handle.try_state(klass)
    end

    # The command line the app started with, which a restart runs again.
    #
    # Mirrors Tauri's <tt>Manager::env</tt> (lib.rs:760-763), the Env that
    # App::build manages (app.rs:2248-2249).
    #
    # === Example
    #
    #   app.env.args_os.drop(1) # => the script and its arguments
    def env
      state(Env) #: Env
    end

    # Fetches a single window from the manager, or +nil+.
    #
    # === Example
    #
    #   webview.get_window("main")
    def get_window(label)
      app_handle.get_window(label)
    end

    # Fetches a single webview from the manager, or +nil+.
    #
    # === Example
    #
    #   window.get_webview("main")
    def get_webview(label)
      app_handle.get_webview(label)
    end

    # Fetches the window that has the keyboard focus, or +nil+ when none
    # of the app's windows has it.
    #
    # Asks each window Window#is_focused in turn; a window that cannot
    # answer, because it is closing, counts as not focused.
    #
    # Mirrors Tauri's Manager::get_focused_window (lib.rs:554-559,
    # manager/mod.rs:642-650).
    #
    # === Example
    #
    #   app.get_focused_window&.label  #=> "main"
    def get_focused_window
      windows.values.find do |window|
        window.is_focused
      rescue Error::Runtime
        false
      end
    end

    # Fetches a single webview window, a WebviewWindow, or +nil+.
    #
    # A webview window is a window holding one webview with its own label,
    # which WebviewWindowBuilder makes. A webview in a window of another
    # label is not one, and answers +nil+.
    #
    # Mirrors Tauri's Manager::get_webview_window (lib.rs:581-591).
    #
    # === Example
    #
    #   app.get_webview_window("main")&.set_title("Ready")
    def get_webview_window(label)
      webview = get_webview(label)
      return nil unless webview

      window = webview.window
      WebviewWindow.new(window:, webview:) if window.is_webview_window
    end

    # Fetches all managed webview windows, keyed by label, as
    # #get_webview_window finds each one.
    #
    # Mirrors Tauri's Manager::webview_windows (lib.rs:593-607).
    #
    # === Example
    #
    #   app.webview_windows.keys  #=> ["main"]
    def webview_windows
      found = {} #: Hash[String, WebviewWindow]
      webviews.to_a.each do |label, webview|
        window = webview.window
        found[label] = WebviewWindow.new(window:, webview:) if window.is_webview_window
      end
      found
    end

    # Fetches all managed windows, keyed by label.
    #
    # === Example
    #
    #   app.windows.keys # => ["main"]
    def windows
      app_handle.windows
    end

    # Fetches all managed webviews, keyed by label.
    #
    # === Example
    #
    #   app.webviews.keys # => ["main"]
    def webviews
      app_handle.webviews
    end

    # The resources table for this manager. Each including class supplies
    # its own: App and AppHandle share the app-level table, while each
    # Window and Webview has a table of its own.
    #
    # === Example
    #
    #   rid = webview.resources_table.add(image)
    def resources_table
      raise NotImplementedError, "#{self.class} must implement #resources_table"
    end
  end
end

# SPDX-SnippetEnd
