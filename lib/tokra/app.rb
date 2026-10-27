# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: App structure adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # The built Tokra application.
  #
  # Created by calling Builder#build. Provides access to the application
  # handle and runs the event loop.
  class App
    include Manager

    # The application handle, safe to pass between Ractors.
    attr_reader :handle

    # The application handle this App manages through, as Manager
    # requires. App is a Manager like AppHandle, Window, and Webview
    # (Tauri app.rs:683-701).
    #
    # === Example
    #
    #   app.app_handle.emit("ready", {})
    def app_handle
      @handle
    end

    # The app-level resources table, shared with AppHandle (Tauri
    # app.rs:683-687).
    #
    # === Example
    #
    #   rid = app.resources_table.add(image)
    def resources_table
      @handle.resources_table
    end

    # The per-app IPC invoke key verified on every message.
    #
    # The key is templated into the injected initialization scripts;
    # frontend messages carrying a different key are logged and dropped.
    # Use it when you build an invoke request by hand. Mirrors Tauri's
    # public App#invoke_key (app.rs:1040-1047).
    #
    # *Security*: never expose this key to third-party scripts. It grants
    # access to the backend from external URLs and iframes.
    #
    # === Example
    #
    #   message = { "cmd" => "greet", "__TAURI_INVOKE_KEY__" => app.invoke_key }
    def invoke_key
      @manager.invoke_key
    end

    # Runs the block on the main thread and returns +nil+, as
    # AppHandle#run_on_main_thread does.
    #
    # Mirrors Tauri's App::run_on_main_thread (app.rs:1137-1140).
    #
    # === Example
    #
    #   app.run_on_main_thread { puts "on the main thread" }
    def run_on_main_thread(&)
      @handle.run_on_main_thread(&)
    end

    # The native name of the display your windows are on, as
    # AppHandle#display_handle answers.
    #
    # Mirrors Tauri's <tt>HasDisplayHandle</tt> for App (app.rs:2361-2367).
    #
    # === Example
    #
    #   app.display_handle  #=> #<data Tokra::RawWindowHandle::WindowsDisplayHandle>
    def display_handle
      @handle.display_handle
    end

    # Default window configuration when not specified.
    DEFAULT_CONFIG = {
      title: "Tokra",
      width: 800.0,
      height: 600.0,
    }.freeze

    # Creates a new App from a configured Builder.
    #
    # This is called by Builder#build and should not be called directly.
    # <tt>native:</tt> can be injected for testing with mock native components.
    def initialize(builder, native: Native) # :nodoc:
      @window_config = DEFAULT_CONFIG.merge(builder.__send__(:window_config))
      config = Config.new(
        identifier: @window_config[:identifier]&.to_s,
        product_name: @window_config[:product_name]&.to_s,
        version: @window_config[:version]&.to_s
      )
      @manager = AppManager.new(config:, webviews: {}, windows: {})
      # The thread that builds the app is its main thread until App#run
      # attaches the event loop, which makes the running thread the main one.
      @runtime_context = RuntimeContext.new
      @handle = AppHandle.new(@manager, state_manager: builder.__send__(:state_manager),
        runtime_context: @runtime_context)
      @builder = builder
      @with_global_tauri = builder.__send__(:with_global_tauri?)

      # Register core plugins, mirroring Tauri app.rs (App::build)
      @handle.plugin(Resources::Plugin.new(@handle))
      @handle.plugin(Image::Plugin.new(@handle))
      # Store class references to avoid dynamic constant lookups
      @event_loop_class = native.const_get(:EventLoop)
      @window_class = native.const_get(:Window)
      @webview_class = native.const_get(:WebView)
    end

    # Runs the application event loop.
    #
    # Creates the native window and webview, then runs the event loop.
    # The block receives (handle, event) for each runtime event:
    # RunEvent::Ready before the loop starts, RunEvent::WindowEvent when
    # the window is asked to close, and RunEvent::Exit as the loop ends.
    # Registered plugins hear each one first.
    #
    # The native loop never returns. When it ends, it raises SystemExit
    # with the loop's exit code, the way Kernel#exit ends a process, so
    # +ensure+ clauses and +at_exit+ hooks run and buffered output reaches
    # its pipe or file. Code after this call does not run; put shutdown
    # work in a RunEvent::Exit handler. A <tt>rescue Exception</tt> or
    # <tt>rescue SystemExit</tt> around this call catches the exit, and the
    # process keeps running unless you re-raise it.
    #
    # === Example
    #
    #   app.run do |_handle, event|
    #     puts "bye" if event.is_a?(Tokra::RunEvent::Exit)
    #   end
    def run(&callback)
      # Call setup hook before anything else
      @builder.__send__(:setup_hook)&.call(self)

      # Create native components via injected factory
      event_loop = @event_loop_class.new
      proxy = event_loop.create_proxy
      @runtime_context.attach(proxy)

      # If a Rack app was configured, build the adapter that serves it
      # over tokra:// (ADR 004: Builder aggregates the app, App instantiates
      # the Handler). The Rack app runs on the main Ractor for now.
      rack_app = @builder.__send__(:rack_app)
      @rack_handler = ::Rack::Handler::Tokra.new(rack_app, proxy) if rack_app

      native_window = @window_class.new(event_loop)
      native_window.set_title(@window_config[:title].to_s)
      native_window.set_size(@window_config[:width].to_f, @window_config[:height].to_f)

      # Wrap the native window and register in manager
      window = Window.new(label: "main", native: native_window, app_handle: @handle)
      @window = window
      @handle.windows["main"] = window

      # Create and wrap the webview, register in manager
      native_webview = @webview_class.new_with_protocol(native_window, proxy, initialization_scripts)
      webview = Webview.new(label: "main", native: native_webview, window:, app_handle: @handle)
      @webview = webview
      @handle.webviews["main"] = webview

      # Emit Ready event
      emit_run_event(RunEvent::Ready.new, callback)

      # Run the event loop, dispatching events. It never returns: when the
      # loop ends it raises SystemExit with the loop's exit code, so
      # RunEvent::Exit arrives from inside the loop as
      # Native::LoopDestroyedEvent, as in Tauri's runtime.
      begin
        event_loop.run(
          lambda { |event|
            dispatch_event(event, callback, native_window, proxy)
          }
        )
      ensure
        # The loop is gone: a call from another thread can no longer reach
        # the main thread, and one waiting for an answer will never get it.
        @runtime_context.close
      end
    end

    # Sends a run event to every registered plugin, then the user callback.
    #
    # Plugins hear events before the callback, matching Tauri's dispatch
    # order in on_event_loop_event (app.rs).
    private def emit_run_event(event, callback)
      @manager.plugins.on_event(@handle, event)
      callback&.call(@handle, event)
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Initialization script assembly adapted from
    # tauri/crates/tauri/src/manager/webview.rs and app.rs

    # The channel-data command name (ipc/channel.rs FETCH_CHANNEL_DATA_COMMAND).
    FETCH_CHANNEL_DATA_COMMAND = "plugin:__TAURI_CHANNEL__|fetch"

    # The window[...] function the emit script calls; the injected event
    # script defines it. Tauri generates random names per app
    # (listeners.rs); Tokra fixes them, matching Native.emit_js_script.
    EMIT_FUNCTION_NAME = "__TAURI_EMIT__"

    # The window[...] object holding event listeners by event name.
    LISTENERS_OBJECT_NAME = "__TAURI_LISTENERS__"

    # Assembles the webview initialization scripts in Tauri's injection
    # order (manager/webview.rs:160-192): the __TAURI_INTERNALS__
    # bootstrap, the invoke transport, webview metadata, and the init.js
    # bundle (pattern, ipc router, core, events). Each registered plugin's
    # initialization_script follows, wrapped in an IIFE
    # (manager/webview.rs:124-128, 194; plugin.rs:918-933).
    #
    # When with_global_tauri is set, the vendored @tauri-apps/api bundle is
    # appended last, exposing the whole API as window.__TAURI__
    # (manager/webview.rs:210-215). This is Tauri's own mechanism for
    # running its API in a webview with no frontend bundler. Tauri's list
    # also carries plugin global API scripts, which its build scripts
    # collect at compile time; no Tokra plugin ships one yet (Plan 016).
    private def initialization_scripts
      scripts = [
        bootstrap_script,
        invoke_initialization_script,
        metadata_script,
        init_script,
      ]
      scripts.concat(@manager.plugins.initialization_script)
      scripts << global_api_script if @with_global_tauri
      scripts
    end

    # The vendored @tauri-apps/api IIFE (bundle.global.js), synced from the
    # submodule by rake sync:tauri. Injecting it defines window.__TAURI__.
    private def global_api_script
      Native.load_js_template("bundle.global.js")
    end

    # Defines window.isTauri and the bare __TAURI_INTERNALS__ object
    # every later script extends (manager/webview.rs:160-175).
    private def bootstrap_script
      <<~JS
        Object.defineProperty(window, 'isTauri', {
          value: true,
        });

        if (!window.__TAURI_INTERNALS__) {
          Object.defineProperty(window, '__TAURI_INTERNALS__', {
            value: {
              plugins: {}
            }
          })
        }
      JS
    end

    # The invoke transport (ipc-protocol.js): defines
    # __TAURI_INTERNALS__.postMessage with the invoke key baked in
    # (app.rs InvokeInitializationScript).
    private def invoke_initialization_script
      render_js_template("ipc-protocol.js.erb",
        process_ipc_message_fn: Native.load_js_template("process-ipc-message-fn.js"),
        os_name: JSON.generate(os_name),
        fetch_channel_data_command: JSON.generate(FETCH_CHANNEL_DATA_COMMAND),
        invoke_key: JSON.generate(@manager.invoke_key))
    end

    # Webview identity for the frontend API (manager/webview.rs:177-188).
    private def metadata_script
      <<~JS
        Object.defineProperty(window.__TAURI_INTERNALS__, 'metadata', {
          value: {
            currentWindow: { label: "main" },
            currentWebview: { label: "main" }
          }
        })
      JS
    end

    # The init.js bundle (manager/webview.rs initialization_script):
    # pattern, the __TAURI_INTERNALS__.ipc router, core.js, and the
    # event-delivery script. freeze_prototype is config-gated off in
    # Tauri's default and omitted here.
    private def init_script
      render_js_template("init.js.erb",
        freeze_prototype: "",
        pattern_script: render_js_template("pattern.js.erb",
          pattern: JSON.generate({ pattern: "brownfield" })),
        ipc_script: render_js_template("ipc.js.erb",
          isolation_origin: JSON.generate("")),
        core_script: render_js_template("core.js.erb",
          os_name: JSON.generate(os_name),
          protocol_scheme: JSON.generate("http")),
        event_initialization_script: render_js_template("event_init.js.erb",
          function_name: EMIT_FUNCTION_NAME,
          listeners: LISTENERS_OBJECT_NAME))
    end

    # Renders a vendored Tauri script template. Values arrive as JS
    # literals: JSON-encoded scalars for TEMPLATE markers, raw scripts
    # for RAW markers.
    private def render_js_template(name, values)
      ERB.new(Native.load_js_template(name)).result_with_hash(values)
    end

    # The operating system name as Tauri's scripts expect it
    # (std::env::consts::OS values).
    private def os_name
      case RUBY_PLATFORM
      when /darwin/ then "macos"
      when /linux/ then "linux"
      when /mingw|mswin/ then "windows"
      else "unknown"
      end
    end

    # SPDX-SnippetEnd

    private def dispatch_event(event, callback, window, proxy)
      # Use is_a? instead of case/when to support mock event injection in tests
      if event.is_a?(Native::TaskEvent)
        @runtime_context.handle_task
      elsif event.is_a?(Native::HttpRequestEvent)
        dispatch_http_request(event, proxy)
      elsif event.is_a?(Native::IpcEvent)
        dispatch_ipc(event)
      elsif event.is_a?(Native::PageLoadEvent)
        dispatch_page_load(event)
      elsif event.is_a?(Native::WindowCloseEvent)
        dispatch_window_event(window, WindowEvent::CloseRequested.new, callback)
      elsif event.is_a?(Native::DragDropEvent)
        dispatch_webview_event(event)
      elsif event.is_a?(Native::LoopDestroyedEvent)
        # The runtime's loop-destroyed event becomes RunEvent::Exit
        # (tauri-runtime-wry lib.rs:4046-4047, app.rs:1304-1305).
        emit_run_event(RunEvent::Exit.new, callback)
      end
    end

    private def dispatch_http_request(event, proxy)
      # The ipc:// transport shares the HttpRequest event shape with the
      # tokra:// content protocol; route on the URI scheme (Plan 015 D1/D3).
      return dispatch_ipc_protocol(event, proxy) if ipc_protocol_request?(event.uri)

      sync_protocols = @builder.__send__(:uri_scheme_protocols)
      async_protocols = @builder.__send__(:async_uri_scheme_protocols)

      # Try sync protocol first (for backwards compatibility)
      if sync_protocols && (handler = sync_protocols["tokra"])
        ctx = UriSchemeContext.new(app_handle: @handle, webview_label: "main")
        response = handler.call(ctx, event)
        header_pairs = response.headers.map { |k, v| [k.to_s, v.to_s] } #: Array[[String, String]]
        proxy.respond(event.request_id, response.status, header_pairs, response.body)
      elsif async_protocols && (handler = async_protocols["tokra"])
        ctx = UriSchemeContext.new(app_handle: @handle, webview_label: "main")
        responder = UriSchemeResponder.new(port: proxy, request_id: event.request_id)
        handler.call(ctx, event, responder)
      elsif (rack_handler = @rack_handler)
        # A configured Rack app is the tokra:// content server; the adapter
        # translates the request and responds through the proxy itself.
        rack_handler.call(event)
      end
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: IPC dispatch adapted from tauri/src/ipc/protocol.rs
    #                      and tauri/src/webview/mod.rs on_message

    # Handles a window.ipc.postMessage invoke (ipc/protocol.rs
    # handle_ipc_message).
    #
    # Deviation: Tauri deserializes a strict message and, on failure, evals
    # <tt>console.error(...)</tt> in the webview (ipc/protocol.rs:422-430).
    # Tokra logs unparseable messages to stderr and treats a message
    # without integer callback ids as fire-and-forget, so hand-rolled
    # postMessage calls keep working (ADR 009).
    private def dispatch_ipc(event)
      parsed = JSON.parse(event.message)
      return warn("failed to parse IPC message: not a JSON object") unless parsed.is_a?(Hash)

      received_key = parsed["__TAURI_INVOKE_KEY__"]
      unless received_key == @manager.invoke_key
        # Log and drop, exactly as Tauri does (webview/mod.rs on_message):
        # a frame the app did not initialize gets no response at all
        return warn(
          "__TAURI_INVOKE_KEY__ expected #{@manager.invoke_key} but received #{received_key}"
        )
      end

      cmd = parsed["cmd"] || ""
      raw_payload = parsed["payload"]
      empty_payload = {} #: Hash[String, json_value]
      payload = raw_payload.is_a?(Hash) ? raw_payload : empty_payload
      responder = build_ipc_responder(parsed["callback"], parsed["error"])

      route_invoke(cmd, payload, responder, event.url)
    rescue JSON::ParserError => e
      warn("failed to parse IPC message: #{e.message}")
    end

    # Routes a parsed invoke to its handler, shared by both transports.
    #
    # Tauri routes the postMessage and ipc:// transports through one
    # method (webview/mod.rs on_message): plugin:-prefixed commands go to
    # the plugin store, everything else to the app invoke_handler, and an
    # unclaimed command rejects with <tt>Command NAME not found</tt>. Each
    # transport supplies only what differs: how it read the key, parsed
    # the payload, where it found the origin, and what its responder does.
    #
    # Tauri's on_message also resolves ACL/capabilities here. Tokra has no
    # capability system yet (TODO 001 #9), so as a stopgap it rejects every
    # invoke whose origin is not the app's own (local_url?) with Tauri's
    # release-build ACL message. That is stricter than Tauri, which lets a
    # remote origin call app commands when the app has no ACL manifest;
    # the stopgap goes away when capabilities land (ADR 010). On Linux the
    # postMessage origin is the webview's top-level URI, not the posting
    # frame's (wry's WebKitGTK backend reports it so, as Tauri sees it too),
    # so a foreign frame passes the check over postMessage there; ipc://
    # still rejects it by its Origin header.
    #
    # A handler that raises does not leave the frontend waiting: the error
    # is logged and, if the invoke has not responded yet, it rejects with
    # the exception message, the way a Tauri command returning Err does.
    private def route_invoke(cmd, payload, responder, origin)
      plugin_name, command = plugin_command(cmd)
      invoke = Ipc::Invoke.new(
        command: command || cmd,
        payload:,
        responder:,
        webview: @webview # steep:ignore ArgumentTypeMismatch
      )
      return invoke.reject("Command #{cmd} not allowed by ACL") unless local_url?(origin)

      handled = if plugin_name
        @manager.plugins.extend_api(plugin_name, invoke)
      else
        @builder.__send__(:invoke_handler_hook)&.call(invoke)
      end
      invoke.reject("Command #{command || cmd} not found") unless handled
    rescue => e
      warn("command #{cmd} failed: #{e.class}: #{e.message}")
      invoke&.reject(e.message)
    end

    # Builds a responder that evaluates Tauri's callback script in the
    # calling webview: success resolves the callback ID, failure the
    # error ID. Mirrors responder_eval (ipc/protocol.rs). Messages
    # without integer callback IDs (hand-rolled postMessage calls)
    # get no responder: fire and forget.
    #
    # Deviation: on platforms other than macOS, Tauri sends object and
    # array results over a Channel instead of eval (ipc/protocol.rs:
    # 371-388). Tokra's Ipc::Channel carries no invoke results, so this
    # always evaluates runCallback, which the frontend handles identically.
    #
    # The responder runs synchronously on the Main Ractor and captures
    # the webview, so it must never cross a Ractor boundary. The Worker
    # Ractor phase (ADR 001) will swap this implementation for a proxy
    # round-trip without touching handlers.
    private def build_ipc_responder(callback, error)
      return nil unless callback.is_a?(Integer) && error.is_a?(Integer)

      webview = @webview
      return nil unless webview

      lambda do |success, json|
        id = success ? callback : error
        webview.eval(Ipc::FormatCallback.format_raw(id, json))
      end
    end

    # Splits a plugin:NAME|command invoke into [NAME, command], or returns
    # +nil+ for an app command. The plugin store routes on NAME and the
    # plugin's extend_api hook sees the bare command, exactly as Tauri does
    # in webview/mod.rs (1793-1799): the name is the first | token and the
    # command the second, so <tt>plugin:a|b|c</tt> runs command +b+. A
    # missing | separator yields an empty command.
    private def plugin_command(cmd)
      return nil unless cmd.start_with?("plugin:")

      tokens = cmd.delete_prefix("plugin:").split("|", -1)
      [tokens[0] || "", tokens[1] || ""]
    end

    # The URL Tokra serves its own pages from: tokra://localhost on macOS
    # and Linux, http://tokra.localhost on Windows, where WebView2 serves
    # custom protocols over http (wry webview2 custom_protocol_workaround).
    # Mirrors tauri_protocol_url (manager/mod.rs:331-338); Tokra does not
    # enable wry's https scheme.
    private def tokra_protocol_url
      (os_name == "windows") ? URI("http://tokra.localhost") : URI("tokra://localhost")
    end

    # Whether +url+ belongs to the app: same scheme and host as
    # tokra_protocol_url, the first arm of Tauri's is_local_url
    # (webview/mod.rs:1680-1688). Tokra serves no devUrl and routes every
    # registered protocol through tokra://, so the other arms do not apply.
    private def local_url?(url)
      parsed = URI.parse(url.to_s)
      protocol = tokra_protocol_url
      parsed.scheme.to_s.downcase == protocol.scheme && parsed.host.to_s.downcase == protocol.host
    rescue URI::InvalidURIError
      false
    end

    # Raised internally when an ipc:// request is malformed: a missing or
    # non-numeric Tauri-Callback/Tauri-Error, a missing Tauri-Invoke-Key,
    # a missing or invalid Origin, unparseable JSON, or an unknown or
    # unimplemented content type. It mirrors the Err(String) arm of
    # parse_invoke_request (ipc/protocol.rs), surfaced to the client as
    # 500 text/plain. It never escapes App.
    class IpcProtocolError < Error # :nodoc:
    end

    # CORS headers stamped on every ipc:// reply, mirroring the shared
    # respond closure in ipc/protocol.rs (48-57): the client reads the
    # Tauri-Response header cross-origin, so it must be exposed.
    IPC_CORS_HEADERS = [
      ["Access-Control-Allow-Origin", "*"],
      ["Access-Control-Expose-Headers", "Tauri-Response"],
    ].freeze

    # The largest callback id: Tauri's CallbackFn wraps a u32
    # (ipc/mod.rs:586).
    MAX_CALLBACK_ID = (2 ** 32) - 1

    # A Content-Type token (RFC 9110 tchar), for telling a parseable media
    # type from garbage the way mime's parser does.
    MEDIA_TYPE = %r{\A[!\#$%&'*+\-.^_`|~0-9A-Za-z]+/[!\#$%&'*+\-.^_`|~0-9A-Za-z]+\z}

    # Serves the ipc:// custom protocol, Tauri's desktop-default invoke
    # transport (ipc/protocol.rs get handler). POST carries an invoke;
    # OPTIONS is the CORS preflight; any other method is 405.
    private def dispatch_ipc_protocol(event, proxy)
      case event.method
      when "POST"
        dispatch_ipc_protocol_post(event, proxy)
      when "OPTIONS"
        preflight = [["Access-Control-Allow-Headers", "*"]] #: Array[[String, String]]
        proxy.respond(event.request_id, 200, preflight + IPC_CORS_HEADERS, "")
      else
        respond_ipc_error(proxy, event.request_id, 405, "only POST and OPTIONS are allowed")
      end
    end

    # Handles a POST to ipc://: parse per Tauri, verify the invoke key, then
    # route through the shared dispatcher with an HTTP responder.
    #
    # A malformed request replies 500 text/plain with the parse error
    # (ipc/protocol.rs:143-151). A well-formed request with a mismatched key
    # logs Tauri's exact message and drops the responder with no reply
    # (webview/mod.rs:1728-1744). wry's responder has no Drop (wry
    # src/lib.rs:440-455), so nothing answers the request: the page's fetch
    # stays pending and the invoke never settles, as in Tauri. The client
    # does not fall back to postMessage, because its fetch never rejects.
    private def dispatch_ipc_protocol_post(event, proxy)
      cmd, invoke_key, origin, payload = parse_ipc_protocol_request(event)

      unless invoke_key == @manager.invoke_key
        proxy.drop_response(event.request_id)
        return warn(
          "__TAURI_INVOKE_KEY__ expected #{@manager.invoke_key} but received #{invoke_key}"
        )
      end

      responder = build_ipc_protocol_responder(proxy, event.request_id)
      route_invoke(cmd, payload, responder, origin)
    rescue IpcProtocolError => e
      respond_ipc_error(proxy, event.request_id, 500, e.message)
    end

    # Parses an ipc:// POST into [cmd, invoke_key, origin, payload], raising
    # IpcProtocolError on any malformed part, in Tauri's order
    # (ipc/protocol.rs:435-538): the content type, Tauri-Invoke-Key, Origin
    # (present and a valid URL), Tauri-Callback and Tauri-Error (present
    # and u32), then the body. The command is the percent-decoded URL path
    # (ipc/protocol.rs:443-445). The client reads the callback ids from its
    # own request, so Tokra only validates them.
    private def parse_ipc_protocol_request(event)
      headers = event.headers
      cmd = decode_ipc_command(event.uri)
      content_type = ipc_content_type(headers)

      invoke_key = http_header(headers, "Tauri-Invoke-Key")
      raise IpcProtocolError, "missing Tauri-Invoke-Key header" unless invoke_key

      origin = ipc_origin(headers)
      validate_ipc_callback_id(headers, "Tauri-Callback", "callback")
      validate_ipc_callback_id(headers, "Tauri-Error", "error")

      [cmd, invoke_key, origin, parse_ipc_payload(content_type, event.body)]
    end

    # The command name: the URL path with the leading slash removed and
    # percent-decoded (ipc/protocol.rs:443-445). convertFileSrc encodes it
    # with encodeURIComponent (core.js). Like Tauri's percent_decode and
    # decode_utf8_lossy, decoding never fails: a stray % or an unencoded
    # character passes through, and invalid UTF-8 becomes U+FFFD.
    private def decode_ipc_command(uri)
      path = uri.sub(%r{\A[^:/?#]+://[^/?#]*}, "")[/\A[^?#]*/].to_s.delete_prefix("/")
      path.b.gsub(/%\h\h/) { |escape| escape[1, 2].to_s.to_i(16).chr }
        .force_encoding(Encoding::UTF_8).scrub
    end

    # The request content type, defaulting to application/octet-stream
    # when absent (ipc/protocol.rs:452-458). Like Tauri's Mime comparison,
    # parameters count: <tt>application/json; charset=utf-8</tt> is not
    # <tt>application/json</tt>. A value that is not a media type raises
    # <tt>unknown content type</tt>.
    private def ipc_content_type(headers)
      raw = http_header(headers, "Content-Type")
      return "application/octet-stream" unless raw

      essence, parameters = raw.split(";", 2)
      essence = essence.to_s.strip.downcase
      raise IpcProtocolError, "unknown content type" unless MEDIA_TYPE.match?(essence)

      parameters ? "#{essence};#{parameters}" : essence
    end

    # The Origin header, which must be present and an absolute URL
    # (ipc/protocol.rs:491-499). Tauri parses it with the url crate, which
    # rejects a bare <tt>null</tt> origin; an absolute URI is the Ruby
    # equivalent.
    private def ipc_origin(headers)
      origin = http_header(headers, "Origin")
      raise IpcProtocolError, "missing Origin header" unless origin
      raise IpcProtocolError, "Origin header is not a valid URL" unless absolute_url?(origin)

      origin
    end

    private def absolute_url?(value)
      URI.parse(value).absolute?
    rescue URI::InvalidURIError
      false
    end

    # Parses the request body by content type. JSON parses as UTF-8, and an
    # empty body is the empty object (ipc/protocol.rs:525-538). A non-object
    # JSON value also becomes the empty object: Ruby handlers index the
    # payload by key, and Tauri's own key lookup on a non-object reports a
    # missing key, which is what the empty object produces (Plan 016 #15).
    # An empty octet-stream body is the payload-less invoke; raw bodies are
    # unimplemented (Plan 015 Out of Scope).
    private def parse_ipc_payload(content_type, body)
      empty = {} #: Hash[String, json_value]
      case content_type
      when "application/json"
        return empty if body.empty?

        parsed = JSON.parse(body.dup.force_encoding(Encoding::UTF_8))
        parsed.is_a?(Hash) ? parsed : empty
      when "application/octet-stream"
        return empty if body.empty?

        raise IpcProtocolError, "raw request bodies are not implemented"
      else
        raise IpcProtocolError, "content type #{content_type} is not implemented"
      end
    rescue JSON::ParserError => e
      raise IpcProtocolError, e.message
    end

    # Validates that a callback-id header is present and a u32, with the
    # grammar of Rust's u32::from_str: an optional + and ASCII digits, no
    # whitespace, within range (ipc/protocol.rs:501-520).
    private def validate_ipc_callback_id(headers, header_name, kind)
      value = http_header(headers, header_name)
      raise IpcProtocolError, "missing #{header_name} header" unless value
      return if value.match?(/\A\+?[0-9]+\z/) && value.to_i <= MAX_CALLBACK_ID

      raise IpcProtocolError, "Tauri #{kind} header value must be a numeric string"
    end

    # A case-insensitive header lookup over the [name, value] pairs the
    # native layer forwards. HTTP header names are case-insensitive, and the
    # http crate wry uses hands them over lowercased.
    private def http_header(headers, name)
      target = name.downcase
      pair = headers.find { |(key, _value)| key.downcase == target }
      pair&.last
    end

    # Builds the ipc:// responder: it answers the HTTP request rather than
    # evaluating runCallback, since the client reads the response and calls
    # runCallback itself (ipc-protocol.js). Success and error both serialize
    # as application/json, distinguished by the Tauri-Response header, and
    # both reply 200 (ipc/protocol.rs:107-139).
    private def build_ipc_protocol_responder(proxy, request_id)
      lambda do |success, json|
        headers = [
          ["Tauri-Response", success ? "ok" : "error"],
          ["Content-Type", "application/json"],
        ] #: Array[[String, String]]
        proxy.respond(request_id, 200, headers + IPC_CORS_HEADERS, json)
      end
    end

    # Replies to an ipc:// request with a plain-text error and the CORS
    # headers, used for the 500 malformed and 405 non-POST paths.
    private def respond_ipc_error(proxy, request_id, status, message)
      headers = [["Content-Type", "text/plain"]] #: Array[[String, String]]
      proxy.respond(request_id, status, headers + IPC_CORS_HEADERS, message)
    end

    # True when a forwarded HTTP request is an ipc:// invoke. On Windows
    # the page fetches http://ipc.localhost/, but wry reverts that to
    # ipc://localhost/ before calling the protocol handler (webview2
    # prepare_request), so every platform arrives here as ipc://.
    private def ipc_protocol_request?(uri)
      uri.start_with?("ipc://")
    end

    # SPDX-SnippetEnd

    private def dispatch_page_load(event)
      hook = @builder.__send__(:on_page_load_hook)
      return unless hook

      payload = PageLoadPayload.new(url: event.url, started: event.started?)
      hook.call(nil, payload) # webview object not yet wired
    end

    private def dispatch_window_event(window, event, callback)
      # Notify window event listeners
      @builder.__send__(:window_event_listeners)&.each do |listener|
        listener.call(window, event)
      end

      # Also emit as RunEvent::WindowEvent
      emit_run_event(RunEvent::WindowEvent.new(label: "main", event:), callback)
    end

    private def dispatch_webview_event(native_event)
      listeners = @builder.__send__(:webview_event_listeners)
      return unless listeners&.any?

      # Convert Native::DragDropEvent to WebviewEvent::DragDrop
      # Paths come from Rust as strings, convert to Pathname per Tauri's PathBuf semantics
      drag_event = case native_event.event
      when "enter"
        paths = native_event.paths.map { |p| Pathname.new(p) }
        DragDropEvent::Enter.new(paths, PhysicalPosition.new(native_event.x, native_event.y))
      when "over"
        DragDropEvent::Over.new(PhysicalPosition.new(native_event.x, native_event.y))
      when "drop"
        paths = native_event.paths.map { |p| Pathname.new(p) }
        DragDropEvent::Drop.new(paths, PhysicalPosition.new(native_event.x, native_event.y))
      when "leave"
        DragDropEvent::Leave.new
      else
        return # Unknown event type, ignore
      end

      webview_event = WebviewEvent::DragDrop.new(drag_event)

      listeners.each do |listener|
        listener.call(nil, webview_event) # webview object not yet wired
      end
    end
  end
end

# SPDX-SnippetEnd
