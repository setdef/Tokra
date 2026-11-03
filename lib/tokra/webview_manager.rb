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
    # and Linux, http://tokra.localhost on Windows, where WebView2 serves
    # custom protocols over http (wry webview2 custom_protocol_workaround).
    # Mirrors tauri_protocol_url (manager/mod.rs:331-338); Tokra does not
    # enable wry's https scheme.
    def self.tokra_protocol_url(os)
      (os == "windows") ? URI("http://tokra.localhost") : URI("tokra://localhost")
    end

    # A manager for the webviews of the app +manager+, an AppManager, on
    # the platform +os_name+ names, as App#os_name gives it, injecting the
    # @tauri-apps/api bundle when +with_global_tauri+.
    def initialize(manager, os_name:, with_global_tauri: false)
      @manager = manager
      @os_name = os_name
      @with_global_tauri = with_global_tauri
    end

    # The characters the url crate percent-encodes as it joins a relative
    # URL: in its path the C0 controls, space, <tt>"</tt>, <tt><</tt>,
    # <tt>></tt>, <tt>`</tt>, <tt>{</tt>, <tt>}</tt>, DEL, and anything
    # outside ASCII; in its query the same but <tt>`</tt>, <tt>{</tt>, and
    # <tt>}</tt>; in its fragment the same as its path but <tt>{</tt> and
    # <tt>}</tt>. A <tt>%</tt> stays as written everywhere (url 2.5.8
    # src/parser.rs:20-46).
    PATH_ENCODED = /[\x00-\x20"<>`{}\x7F]|[^\x00-\x7F]/
    QUERY_ENCODED = /[\x00-\x20"<>\x7F]|[^\x00-\x7F]/ # :nodoc:
    FRAGMENT_ENCODED = /[\x00-\x20"<>`\x7F]|[^\x00-\x7F]/ # :nodoc:

    # The address +url+, a WebviewUrl, names, as prepare_webview resolves
    # it (manager/webview.rs:414-446). An App path joins the app URL,
    # except <tt>index.html</tt>, which is the app URL itself; the others
    # load as given, a <tt>data:</tt> URL included (plan 052, decision 11).
    #
    # Tokra's app URL keeps its path's slash, <tt>tokra://localhost/</tt>,
    # where Tauri's is the bare <tt>tauri://localhost</tt>, so every Tokra
    # page is still asked for as it was. The path is encoded as the url
    # crate's join encodes it (PATH_ENCODED and its kin), so
    # <tt>page.html#intro</tt> keeps its fragment and <tt>a%20b.html</tt>
    # its escape.
    #
    # The path is cleaned first as the url crate cleans its input: tab,
    # LF, and CR are dropped anywhere, C0 controls and space are trimmed
    # from both ends, and against an http app URL, which is special, a
    # <tt>\\</tt> in the path is a <tt>/</tt> (url 2.5.8
    # src/parser.rs:225-245, 284-297, 912).
    #
    # *Deviations*: where the url crate keeps a character that Ruby's URI
    # refuses, #build raises URI::InvalidURIError, and Tauri's join, whose
    # result it unwraps, never fails there: a <tt>|</tt> or <tt>^</tt> in
    # the path; a <tt>\\</tt> in the path off Windows, where
    # <tt>tokra://</tt> is not special; a second <tt>#</tt>; and a
    # <tt>%</tt> not followed by two hex digits. A <tt>`</tt> in the
    # fragment is encoded, as the url crate encodes it. And Ruby's join encodes a query's <tt>'</tt> and
    # <tt>`</tt>, which the url crate keeps, except an http URL's
    # <tt>'</tt> (url 2.5.8 src/parser.rs:45-46).
    def webview_url(url)
      case url
      when WebviewUrl::App
        app_url = URI.join(WebviewManager.tokra_protocol_url(@os_name).to_s, "/")
        path = url.path.to_s
        return app_url.to_s if path == "index.html"

        special = app_url.scheme == "http"
        URI.join(app_url.to_s, WebviewManager.encode_relative(path, special:)).to_s
      when WebviewUrl::External, WebviewUrl::CustomProtocol then url.url.to_s
      else raise TypeError, "wrong argument type #{url.class} (expected a Tokra::WebviewUrl)"
      end
    end

    # +relative+ cleaned and encoded as the url crate does when it joins
    # it to the app URL, +special+ for an http one: its path, its query
    # from the first <tt>?</tt>, and its fragment from the first
    # <tt>#</tt>, each with its own set.
    def self.encode_relative(relative, special: false)
      cleaned = relative.sub(/\A[\x00-\x20]+/, "").sub(/[\x00-\x20]+\z/, "").delete("\t\n\r")
      rest, hash, fragment = cleaned.partition("#")
      path, question, query = rest.partition("?")
      path = path.tr("\\", "/") if special
      encode(path, PATH_ENCODED) + question + encode(query, QUERY_ENCODED) + hash + encode(fragment, FRAGMENT_ENCODED)
    end

    # +text+ with each character +set+ matches percent-encoded as UTF-8.
    def self.encode(text, set)
      text.gsub(set) { |char| char.bytes.map { |byte| format("%%%02X", byte) }.join }
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
    # When with_global_tauri is set, the vendored @tauri-apps/api bundle is
    # appended last, exposing the whole API as window.__TAURI__
    # (manager/webview.rs:210-215). This is Tauri's own mechanism for
    # running its API in a webview with no frontend bundler. Tauri's list
    # also carries plugin global API scripts, which its build scripts
    # collect at compile time; no Tokra plugin ships one yet (Plan 016).
    def initialization_scripts(window_label, webview_label)
      scripts = [
        bootstrap_script,
        invoke_initialization_script,
        metadata_script(window_label, webview_label),
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
          os_name: JSON.generate(@os_name),
          protocol_scheme: JSON.generate("http")),
        event_initialization_script: Event.event_initialization_script(
          @manager.listeners.function_name, @manager.listeners.listeners_object_name
        ))
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
