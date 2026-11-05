# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WebviewManager adapted from tauri/crates/tauri/src/manager/webview.rs

module Tokra
  # What the app's manager does for each webview it makes: the scripts its
  # pages run first, the address a WebviewUrl names, and the steps that
  # join a new webview to the app.
  #
  # Mirrors Tauri's WebviewManager (manager/webview.rs), which AppManager
  # holds; Tokra's AppHandle holds this one.
  class WebviewManager # :nodoc:
    # The event a new webview is announced with (manager/webview.rs:626-634).
    WEBVIEW_CREATED_EVENT = "tauri://webview-created"

    # The URL Tokra serves its own pages from: tokra://localhost on macOS
    # and Linux, and on Windows, where WebView2 serves custom protocols
    # over http or, for a webview built with +https+, over https (wry
    # webview2 custom_protocol_workaround), http://tokra.localhost or
    # https://tokra.localhost. Mirrors tauri_protocol_url
    # (manager/mod.rs:331-338), a Ferro::Url::Url as Tauri's is the url
    # crate's Url.
    def self.tokra_protocol_url(os, https: false)
      return Ferro::Url::Url.parse("tokra://localhost") unless os == "windows"

      Ferro::Url::Url.parse(https ? "https://tokra.localhost" : "http://tokra.localhost")
    end

    # +path+ pushed onto +base+, as Rust's <tt>PathBuf::push</tt> pushes a
    # path: an absolute +path+ stands alone, and otherwise the platform's
    # separator joins them, unless +base+ ends with one. Windows' paths
    # with a drive or a root but not both, such as <tt>C:a</tt>, which
    # Rust treats apart and no identifier is, join as relative ones.
    def self.push(base, path)
      return path if File.absolute_path?(path)

      separator = File::ALT_SEPARATOR || File::SEPARATOR
      base.end_with?(File::SEPARATOR, separator) ? "#{base}#{path}" : "#{base}#{separator}#{path}"
    end

    # A manager for the webviews of the app +manager+, an AppManager, on
    # the platform +os_name+ names, as App#os_name gives it.
    # +data_local_dir+ answers the user's local data directory, a String,
    # or +nil+ when the platform names none, as the dirs crate's
    # <tt>data_local_dir</tt> does (Native.data_local_dir).
    def initialize(manager, os_name:, data_local_dir: -> { Native.data_local_dir })
      @manager = manager
      @os_name = os_name
      @data_local_dir = data_local_dir
    end

    # The address +url+, a WebviewUrl, names, as prepare_webview resolves
    # it (manager/webview.rs:414-446), for a webview built with +https+ or
    # not (WebviewBuilder#use_https_scheme). An App path joins the app URL,
    # except <tt>index.html</tt>, which is the app URL itself; the others
    # load as given, a <tt>data:</tt> URL included (plan 052, decision 11).
    #
    # Tokra's app URL keeps its path's slash, <tt>tokra://localhost/</tt>,
    # where Tauri's is the bare <tt>tauri://localhost</tt>, so every Tokra
    # page is still asked for as it was. The path joins it with the url
    # crate's own join, a Ferro::Url::Url's, as Tauri's does, so it is
    # cleaned and percent-encoded as Tauri's is: <tt>page.html#intro</tt>
    # keeps its fragment, <tt>a%20b.html</tt> its escape, and
    # <tt>a b.html</tt> becomes <tt>a%20b.html</tt>. A path the join
    # refuses, one naming another host such as <tt>//exa mple</tt>, raises
    # Error::InvalidUrl with the url crate's reason. Tauri maps the join's
    # error to the same Error::InvalidUrl and then unwraps it ("this will
    # never fail"), so its app panics (manager/webview.rs:423-427;
    # *deviation*, tier 1: a panic ends Ruby's VM).
    def webview_url(url, https: false)
      case url
      when WebviewUrl::App
        app_url = WebviewManager.tokra_protocol_url(@os_name, https:).join("/")
        path = url.path.to_s
        return app_url.as_str if path == "index.html"

        begin
          app_url.join(path).as_str
        rescue Ferro::Url::ParseError => e
          raise Error::InvalidUrl, e.message
        end
      when WebviewUrl::External, WebviewUrl::CustomProtocol then url.url.as_str
      else raise TypeError, "wrong argument type #{url.class} (expected a Tokra::WebviewUrl)"
      end
    end

    # The data directory a webview is built with, given +data_directory+,
    # the one its builder named or +nil+, as prepare_webview settles it
    # (manager/webview.rs:505-523). On Linux and Windows a webview with
    # none keeps its data in the app's local data directory, the user's
    # local data directory pushed with the config's identifier, or in
    # none when the platform names no local data directory. Whatever the
    # platform, a directory that does not exist is made, with every
    # parent it lacks.
    #
    # Raises Error::Io with the system's reason, in Rust's words, when the
    # directory cannot be made, as Tauri's create_dir_all error is
    # Error::Io (error.rs:53-54).
    def data_directory(data_directory)
      if data_directory.nil? && (@os_name == "linux" || @os_name == "windows")
        local = @data_local_dir.call
        data_directory = WebviewManager.push(local, @manager.config.identifier) if local
      end
      create_dir_all(data_directory) if data_directory && !File.exist?(data_directory)
      data_directory
    end

    # Makes +directory+ and its missing parents with Rust's
    # <tt>std::fs::create_dir_all</tt>, whose error text, Windows' codes
    # included, Error::Io carries.
    private def create_dir_all(directory)
      Native.fs_create_dir_all(directory)
    rescue RuntimeError => e
      raise Error::Io, e.message
    end

    # Joins +webview+ to the app, as attach_webview does
    # (manager/webview.rs:581-636): the manager holds it, every plugin
    # hears webview_created on the main thread, and every listener hears
    # <tt>tauri://webview-created</tt> with its label. Answers +webview+.
    def attach_webview(webview)
      handle = webview.app_handle
      handle.webviews[webview.label] = webview
      plugins = @manager.plugins
      handle.run_on_main_thread { plugins.webview_created(webview) }
      @manager.emit(Event::EmitArgs.serialize(WEBVIEW_CREATED_EVENT, { "label" => webview.label }))
      webview
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Initialization script assembly adapted from
    # tauri/crates/tauri/src/manager/webview.rs and app.rs

    # Assembles the webview initialization scripts in Tauri's injection
    # order (manager/webview.rs:160-192): the __TAURI_INTERNALS__
    # bootstrap, the invoke transport, webview metadata, and the init.js
    # bundle (pattern, ipc router, core, events). Each registered plugin's
    # initialization_script follows, wrapped in an IIFE
    # (manager/webview.rs:124-128, 194; plugin.rs:918-933).
    #
    # When the config's <tt>app.withGlobalTauri</tt> is set, the vendored
    # @tauri-apps/api bundle is appended last, exposing the whole API as
    # window.__TAURI__ (manager/webview.rs:210-215). This is Tauri's own
    # mechanism for running its API in a webview with no frontend bundler;
    # codegen puts the bundle in the context only when the config sets it
    # (tauri-codegen context.rs:430-440). Tauri's list also carries plugin
    # global API scripts, which its build scripts collect at compile time;
    # no Tokra plugin ships one yet (Plan 016; plan 054, decision 20).
    def initialization_scripts(window_label, webview_label, https: false)
      scripts = [
        bootstrap_script,
        invoke_initialization_script,
        metadata_script(window_label, webview_label),
        init_script(https),
      ]
      scripts.concat(@manager.plugins.initialization_script)
      scripts << global_api_script if @manager.config.app.with_global_tauri
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
        os_name: JSON.generate(@os_name),
        fetch_channel_data_command: JSON.generate(Ipc::Channel::FETCH_CHANNEL_DATA_COMMAND),
        invoke_key: JSON.generate(@manager.invoke_key))
    end

    # Webview identity for the frontend API: the labels of the webview's
    # window and of the webview, each a JSON string as serde_json's
    # to_string writes it (manager/webview.rs:177-188).
    def metadata_script(window_label, webview_label)
      <<~JS
        Object.defineProperty(window.__TAURI_INTERNALS__, 'metadata', {
          value: {
            currentWindow: { label: #{JSON.generate(window_label)} },
            currentWebview: { label: #{JSON.generate(webview_label)} }
          }
        })
      JS
    end

    # The init.js bundle (manager/webview.rs initialization_script):
    # pattern, the __TAURI_INTERNALS__.ipc router, core.js, and the
    # event-delivery script. core.js builds custom protocol URLs with the
    # scheme +https+ names, as Tauri's protocol_scheme (manager/webview.rs:385).
    # freeze_prototype is config-gated off in Tauri's default and omitted
    # here.
    private def init_script(https)
      render_js_template("init.js.erb",
        freeze_prototype: "",
        pattern_script: render_js_template("pattern.js.erb",
          pattern: JSON.generate(pattern_object(@manager.pattern))),
        ipc_script: render_js_template("ipc.js.erb",
          isolation_origin: JSON.generate("")),
        core_script: render_js_template("core.js.erb",
          os_name: JSON.generate(@os_name),
          protocol_scheme: JSON.generate(https ? "https" : "http")),
        event_initialization_script: Event.event_initialization_script(
          @manager.listeners.function_name, @manager.listeners.listeners_object_name
        ))
    end

    # The pattern script's object for +pattern+, the context's, as
    # PatternObject serializes: tagged <tt>pattern</tt>, its variant in
    # lowercase (pattern.rs:39-63). Raises TypeError for anything that is
    # not a Tokra pattern.
    private def pattern_object(pattern)
      case pattern
      when Pattern::Brownfield then { "pattern" => "brownfield" }
      else raise TypeError, "wrong argument type #{pattern.class} (expected Tokra::Pattern)"
      end
    end

    # Renders a vendored Tauri script template. Values arrive as JS
    # literals: JSON-encoded scalars for TEMPLATE markers, raw scripts
    # for RAW markers.
    private def render_js_template(name, values)
      ERB.new(Native.load_js_template(name)).result_with_hash(values)
    end

    # SPDX-SnippetEnd
  end
end

# SPDX-SnippetEnd
