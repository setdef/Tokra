# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Webview structure adapted from tauri/crates/tauri/src/webview/mod.rs

module Tokra
  # Webview wrapper holding native webview reference and ResourceTable.
  #
  # Mirrors Tauri's Webview<R> struct. Each webview owns its own
  # resources_table for storing image resources and other managed objects.
  #
  # Plugins access the calling webview through Invoke#webview:
  #
  #   def invoke_handler(invoke)
  #     table = invoke.webview.resources_table
  #     rid = table.add(MyResource.new)
  #     invoke.resolve(rid)
  #   end
  #
  class Webview
    include Manager
    include Listener
    include Emitter

    # The unique label identifying this webview.
    attr_reader :label

    # The app handle for accessing shared state.
    attr_reader :app_handle

    # The native wry WebView handle.
    attr_reader :native

    # Creates a new Webview wrapper.
    #
    # +label+:: a unique identifier for this webview (e.g., "main").
    # +native+:: the Native::WebView handle from wry.
    # +window+:: the parent Window wrapper.
    # +app_handle+:: provides access to app-level state and config.
    def initialize(label:, native:, window:, app_handle:)
      @label = label
      @native = native
      @window = window
      @app_handle = app_handle
      @resources_table = ResourceTable.new
    end

    # The parent window containing this webview.
    def window
      @window
    end

    # Moves this webview to +window+ in the manager's books, so its window
    # events go there (plan 052, decision 2). Phase 4's reparent sets it
    # when it moves the native webview.
    attr_writer :window # :nodoc:

    # Per-webview resource table for managed resources.
    #
    # Resources added here are scoped to this webview. The table
    # is cleared when the webview is destroyed.
    def resources_table
      @resources_table
    end

    # Evaluates JavaScript in this webview and returns +nil+.
    #
    # From another thread the script travels to the main thread and this
    # method returns without waiting for it to run. A script the webview
    # fails to evaluate is logged, never raised, as Tauri's runtime logs it
    # (tauri-runtime-wry lib.rs:1773-1783, 3642-3646). Raises
    # Error::Runtime when the event loop has ended.
    #
    # Mirrors Tauri's Webview::eval (webview/mod.rs:1896-1902).
    #
    # === Example
    #
    #   webview.eval("document.title = 'Ready'")
    def evaluate(script)
      native = @native
      @app_handle.runtime_context.run_on_main_thread do
        native.eval(script)
      rescue RuntimeError => e
        warn(e.message)
      end
    end
    alias eval evaluate

    # Paints the webview's background, behind the page, with +color+, a
    # Tokra::Color, or white for +nil+, and returns +nil+. Runs as
    # #evaluate does; anything but a Color or +nil+ raises TypeError on the
    # calling thread. A color the webview fails to take is logged, never
    # raised, as Tauri's runtime logs it.
    #
    # wry does not implement it on macOS, so there it does nothing. On
    # Windows an alpha other than 0 is taken as 255. Window#set_background_color
    # colors the window behind the webview (plan 041, decision 2).
    #
    # Mirrors Tauri's Webview::set_background_color (webview/mod.rs:2069-2083;
    # tauri-runtime-wry lib.rs:1829-1838, 3745-3750).
    #
    # === Example
    #
    #   webview.set_background_color(Tokra::Color.new(30, 30, 30, 255))
    def set_background_color(color)
      native = @native
      unless color.nil? || color.is_a?(Color)
        raise TypeError, "wrong argument type #{color.class} (expected Tokra::Color)"
      end

      rgba = color && [color.red, color.green, color.blue, color.alpha] #: Native::Window::rgba?
      @app_handle.runtime_context.run_on_main_thread do
        native.set_background_color(rgba)
      rescue RuntimeError => e
        warn("failed to set webview background color: #{e.message}")
      end
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: The page and cookie methods adapted from tauri/crates/tauri/src/webview/mod.rs
    #                      and the webview messages of tauri-runtime-wry/src/lib.rs

    # The address of the page this webview shows, a URI.
    #
    # From another thread this asks the main thread and waits for its
    # answer. Raises Error::InvalidUrl when the address has no scheme, as
    # before WebKitGTK's first load, or Ruby's URI cannot parse it;
    # Error::Runtime "failed to send message to the webview" when the
    # platform cannot tell; and Error::Runtime "failed to receive message
    # from webview" once the webview is closed, or when the event loop
    # has ended.
    #
    # Where wry panics reading the address (macOS unwraps the WKWebView's
    # URL, wkwebview/mod.rs:1244-1246), this raises "failed to send message
    # to the webview" as for wry's error, and Rust prints the panic to
    # standard error; Tauri's app panics there.
    #
    # Mirrors Tauri's Webview::url (webview/mod.rs:1662-1668;
    # tauri-runtime-wry lib.rs:1580-1582, 3758-3765).
    #
    # === Example
    #
    #   webview.url  #=> #<URI::Generic tokra://localhost/>
    def url
      address = query(&:url)
      parsed = URI.parse(address)
      raise Error::InvalidUrl, Error::InvalidUrl::RELATIVE_URL_WITHOUT_BASE unless parsed.absolute?

      parsed
    rescue URI::InvalidURIError => e
      raise Error::InvalidUrl, e.message
    end

    # Loads +url+, a URI::Generic, in this webview, and returns +nil+.
    #
    # Runs as #evaluate does: from another thread it returns without
    # waiting for the load. Anything but a URI raises TypeError on the
    # calling thread, and a relative one ArgumentError "relative URL
    # without a base", as Tauri's Url is always absolute. A URL the
    # webview fails to load is logged, never raised, as Tauri's runtime
    # logs it; a closed webview ignores it. On
    # macOS wry panics on a URL NSURL cannot parse (wkwebview/mod.rs:775),
    # where Tauri's app panics; here that is logged too, with the panic's
    # message.
    #
    # Mirrors Tauri's Webview::navigate (webview/mod.rs:1670-1673;
    # tauri-runtime-wry lib.rs:1598-1607, 3647-3651).
    #
    # === Example
    #
    #   webview.navigate(URI("https://tauri.app"))
    def navigate(url)
      address = absolute(url).to_s
      command("failed to navigate to url #{address}") { |native| native.navigate(address) }
    end

    # Reloads the page this webview shows, and returns +nil+. Runs as
    # #navigate does, and logs a failure as "failed to reload: ...".
    #
    # Mirrors Tauri's Webview::reload (webview/mod.rs:1675-1678;
    # tauri-runtime-wry lib.rs:1609-1618, 3652-3656).
    #
    # === Example
    #
    #   webview.reload
    def reload
      command("failed to reload", &:reload)
    end

    # The cookies in this webview's cookie store that go with requests
    # to +url+, a URI::Generic, as an Array of Cookie, HTTP-only and
    # secure ones included.
    #
    # Only +http+ and +https+ URLs have cookies: cookies a page served over
    # a custom protocol, such as Tokra's own, sets through JavaScript are
    # not in the store. On
    # macOS wry reads every cookie and keeps those whose domain is the
    # URL's host, so there a URL whose host is an IP address answers none.
    #
    # Answers as #cookies does, and raises on the calling thread TypeError
    # for anything but a URI and ArgumentError for a relative one, as
    # #navigate does.
    #
    # Mirrors Tauri's Webview::cookies_for_url (webview/mod.rs:2094-2113;
    # tauri-runtime-wry lib.rs:1704-1717, 3785-3790). For a closed webview
    # Tauri's runtime panics on the channel it leaves unanswered, where
    # this raises "failed to receive message from webview".
    #
    # === Example
    #
    #   webview.cookies_for_url(URI("https://tauri.app"))
    #   #=> [#<data Tokra::Cookie name="session", value="abc", ...>]
    def cookies_for_url(url)
      address = absolute(url).to_s
      query { |native| native.cookies_for_url(address) }.map { |fields| Cookie.from_native(fields) }
    end

    # Every cookie in this webview's cookie store, for every URL, as an
    # Array of Cookie, HTTP-only and secure ones included.
    #
    # Only pages served over +http+ or +https+ have cookies. Cookies a page
    # served over a custom protocol, such as Tokra's own, sets through
    # JavaScript are not in the store.
    #
    # The platform reads its store while the main thread waits:
    #
    # [macOS] wry runs the main run loop until the store answers, for at
    #         most a second or so, and fails when it does not.
    # [Windows] wry runs a nested message loop until WebView2 answers.
    # [Linux] wry runs GTK's main loop until WebKitGTK answers.
    #
    # Window and webview events that arrive meanwhile wait for the loop,
    # and no callback of yours runs inside the wait (plan 052, decision
    # e2-1). From another thread this asks the main thread and waits for
    # its answer. Raises Error::Runtime "failed to send message to the
    # webview" when the platform fails, and "failed to receive message
    # from webview" once the webview is closed or when the event loop has
    # ended.
    #
    # Tauri warns that on Windows this deadlocks inside a synchronous
    # command or event handler (wry issue 583). That needs the call to run
    # inside one of WebView2's own callbacks, and Tokra runs none of your
    # code there: commands, listeners, and page-load hooks run from the
    # event loop.
    #
    # Mirrors Tauri's Webview::cookies (webview/mod.rs:2115-2138;
    # tauri-runtime-wry lib.rs:1719-1721, 3768-3771).
    #
    # === Example
    #
    #   webview.cookies.map(&:name)  #=> ["session", "theme"]
    def cookies
      query(&:cookies).map { |fields| Cookie.from_native(fields) }
    end

    # Puts +cookie+, a Cookie, in this webview's cookie store, replacing
    # one of the same name, domain, and path, and returns +nil+.
    #
    # Runs as #navigate does: from another thread it returns without
    # waiting. Anything but a Cookie raises TypeError on the calling
    # thread. A cookie the platform refuses is logged as "failed to set
    # webview cookie: ...", never raised; a closed webview ignores it. On
    # macOS and Linux the main thread waits for the store, as #cookies
    # does.
    #
    # Some cookies make wry panic, where Tauri's app panics: on macOS one
    # with an empty name or a value holding a line break, which the
    # platform cannot make into a cookie (wkwebview/mod.rs:1082-1083), and
    # on Linux one that expires before the year 1
    # (webkitgtk/mod.rs:981-983). Here that is logged with the panic's
    # message, "failed to set webview cookie: failed to create wkwebview
    # cookie, report this as bug to `wry`" on macOS, and Rust prints the
    # panic to standard error.
    #
    # Mirrors Tauri's Webview::set_cookie (webview/mod.rs:2140-2151;
    # tauri-runtime-wry lib.rs:1723-1733, 3773-3777).
    #
    # === Example
    #
    #   webview.set_cookie(Tokra::Cookie.new(name: "theme", value: "dark", domain: "localhost", path: "/"))
    def set_cookie(cookie)
      raise TypeError, "wrong argument type #{cookie.class} (expected Tokra::Cookie)" unless cookie.is_a?(Cookie)

      fields = cookie.native_fields
      command("failed to set webview cookie") { |native| native.set_cookie(fields) }
    end

    # Takes the cookie that matches +cookie+, a Cookie, out of this
    # webview's cookie store, and returns +nil+. Runs as #set_cookie does,
    # and logs a failure as "failed to delete webview cookie: ...".
    #
    # Mirrors Tauri's Webview::delete_cookie (webview/mod.rs:2153-2164;
    # tauri-runtime-wry lib.rs:1735-1745, 3779-3783).
    #
    # === Example
    #
    #   webview.cookies.each { |cookie| webview.delete_cookie(cookie) }
    def delete_cookie(cookie)
      raise TypeError, "wrong argument type #{cookie.class} (expected Tokra::Cookie)" unless cookie.is_a?(Cookie)

      fields = cookie.native_fields
      command("failed to delete webview cookie") { |native| native.delete_cookie(fields) }
    end

    # Runs a native query on the main thread and answers it, as the
    # runtime's webview getters do: wry's error is FailedToSendMessage,
    # and a closed webview, which answers +nil+, goes unanswered
    # (tauri-runtime-wry lib.rs:196-230, 3758-3792).
    private def query
      native = @native
      answer = @app_handle.runtime_context.getter do
        yield native
      rescue RuntimeError
        raise Error::Runtime, Error::Runtime::FAILED_TO_SEND_MESSAGE
      end
      raise Error::Runtime, Error::Runtime::FAILED_TO_RECEIVE_MESSAGE if answer.nil?

      answer
    end

    # Runs a native command on the main thread, logging its failure after
    # +failure+, as the runtime's handler logs wry's. Every refusal the
    # native side gives is logged, not only wry's RuntimeError: the
    # KeyError, TypeError, ArgumentError, and RangeError a malformed Hash
    # raises (cookie.rs). So the command never raises there, nor ends the
    # loop from another thread's task. Anything else, such as a
    # NoMethodError from a bug, still raises.
    private def command(failure)
      native = @native
      @app_handle.runtime_context.run_on_main_thread do
        yield native
      rescue RuntimeError, KeyError, TypeError, ArgumentError, RangeError => e
        warn("#{failure}: #{e.message}")
      end
    end

    # +url+, which must be an absolute URI::Generic.
    private def absolute(url)
      raise TypeError, "wrong argument type #{url.class} (expected URI::Generic)" unless url.is_a?(URI::Generic)
      raise ArgumentError, Error::InvalidUrl::RELATIVE_URL_WITHOUT_BASE unless url.absolute?

      url
    end

    # SPDX-SnippetEnd

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Page listeners and Listener for Webview adapted from
    #                      tauri/crates/tauri/src/webview/mod.rs

    # Records a page listener for +event+ and +target+, whose callback is
    # +handler+, a callback id from the page: the listener script runs in
    # this webview first, then the registry keeps it. Answers its id.
    #
    # Mirrors Tauri's Webview::listen_js (webview/mod.rs:1904-1927).
    def listen_js(event, target, handler) # :nodoc:
      listeners = @app_handle.manager.listeners
      id = listeners.next_event_id
      evaluate(Event.listen_js_script(listeners.listeners_object_name, target.to_json, event, id, handler))
      listeners.listen_js(event, @label, target, id)
      id
    end

    # Forgets the page listener with +id+ (webview/mod.rs:1929-1935).
    def unlisten_js(event, id) # :nodoc:
      @app_handle.manager.listeners.unlisten_js(event, id)
    end

    # Hands +emit_args+ to the page listeners with +ids+
    # (webview/mod.rs:1937-1944).
    def emit_js(emit_args, ids) # :nodoc:
      evaluate(Event.emit_js_script(@app_handle.manager.listeners.function_name, emit_args, JSON.generate(ids)))
    end

    # Calls the block with each +event+ sent to this webview, by
    # Emitter#emit, or to its label as a Webview or an AnyLabel, and
    # returns the handler's id. Raises Error::IllegalEventName for a bad
    # name.
    #
    # Mirrors Tauri's Webview::listen (webview/mod.rs:2180-2203).
    #
    # === Example
    #
    #   webview.listen("component-loaded") { |event| puts event.payload }
    def listen(event, &handler)
      @app_handle.manager.listen(Event::Name.check(event), EventTarget.webview(@label), &handler)
    end

    # Calls the block with the next +event+ sent to this webview, as
    # #listen does, and returns the handler's id (webview/mod.rs:2205-2219).
    def once(event, &handler)
      @app_handle.manager.once(Event::Name.check(event), EventTarget.webview(@label), &handler)
    end

    # Removes the handler with +id+, whichever target it listens for
    # (webview/mod.rs:2221-2251).
    def unlisten(id)
      @app_handle.manager.unlisten(id)
    end

    # SPDX-SnippetEnd

    # The cursor's position on the desktop, a PhysicalPosition, as
    # AppHandle#cursor_position answers: the desktop's top-left is the
    # origin, so the position does not depend on this webview.
    #
    # Mirrors Tauri's Webview::cursor_position (webview/mod.rs:1473-1481),
    # which asks the app handle.
    #
    # === Example
    #
    #   webview.cursor_position  #=> #<data Tokra::PhysicalPosition x=812.0, y=455.5>
    def cursor_position
      @app_handle.cursor_position
    end

    # Runs the block on the main thread and returns +nil+, as
    # AppHandle#run_on_main_thread does.
    #
    # Mirrors Tauri's Webview::run_on_main_thread (webview/mod.rs:1356-1363).
    #
    # === Example
    #
    #   Thread.new { webview.run_on_main_thread { webview.eval("refresh()") } }
    def run_on_main_thread(&)
      @app_handle.runtime_context.run_on_main_thread(&)
    end
  end
end

# SPDX-SnippetEnd
