# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # The hooks a plugin answers as the app runs.
  #
  # A desktop app grows past what its framework gives it: a clipboard, a
  # logger, global hotkeys, commands of your own. Each of those wants to
  # join the app the same way, hearing its windows and pages, answering
  # its own <tt>plugin:NAME|command</tt> invokes, and setting itself up
  # once the app exists.
  #
  # This class is the plugin's side of that contract: every hook has a
  # default, so a plugin overrides only the ones it needs and #name.
  # Register a plugin with Builder#plugin before the app is built, or
  # with AppHandle#plugin once it runs. Most plugins need no subclass:
  # Plugin::Builder makes one from blocks, as Tauri's plugins are made.
  #
  # Use it to write a plugin whose state lives on the object itself.
  #
  # Mirrors Tauri's Plugin trait (plugin.rs:37-112). The trait's
  # +initialize+ is #initialize_plugin here, since Ruby's +initialize+ is
  # the constructor (plan 064, decision 1).
  #
  # === Examples
  #
  #   class Counter < Tokra::Plugin
  #     def name
  #       "counter"
  #     end
  #
  #     def initialize_plugin(app, config)
  #       super
  #       @count = config ? config.fetch("start") : 0
  #     end
  #
  #     def extend_api(invoke)
  #       return false unless invoke.command == "next"
  #
  #       invoke.resolve(@count += 1)
  #       true
  #     end
  #   end
  #
  #   Tokra::Builder.default.plugin(Counter.new).run(Tokra.generate_context)
  #
  #   # A plugin made with the app's handle, as the core plugins are:
  #   app.handle.plugin(Counter.new(app.handle))
  class Plugin
    # Returns the unique plugin identifier.
    def name
      raise NotImplementedError
    end

    # Makes the plugin. A plugin needs no app to be made: Builder#plugin
    # takes one before the app exists, and #initialize_plugin hands it the
    # app later.
    #
    # [app] the AppHandle, or +nil+ until the plugin is initialized.
    # [config] the plugin's config, readable by subclasses as +config+.
    def initialize(app = nil, config = {})
      @app = app if app
      @config = config
    end

    # Initializes the plugin with +app+, the AppHandle, and +config+, the
    # plugin's slice of the app config's +plugins+: the JSON under its
    # #name, or +nil+ when the config has none. The app calls it once, as
    # it registers the plugin: at once for AppHandle#plugin, and for
    # Builder#plugin in App#run, before the windows the config lists.
    #
    # Raise to fail. The app reports the failure as
    # Error::PluginInitialization, with the plugin's name and your
    # error's message, and does not register the plugin.
    #
    # Records +app+ and +config+ for the +app+ and +config+ readers, and
    # returns +nil+. Tauri's default does nothing; the readers are Tokra's,
    # so a subclass that overrides this calls +super+ to keep them.
    #
    # Mirrors the Plugin trait's +initialize+ (plugin.rs:41-49).
    #
    # === Example
    #
    #   def initialize_plugin(app, config)
    #     super
    #     app.manage(Store.new(config))
    #   end
    public def initialize_plugin(app, config)
      @app = app
      @config = config
      nil
    end

    protected

    # The application handle. Available to subclasses.
    attr_reader :app

    # The plugin's config. Available to subclasses.
    attr_reader :config

    # Called with the app handle for every run loop event.
    #
    # Override in subclasses to handle events. App delivers
    # RunEvent::Ready, RunEvent::WindowEvent, RunEvent::MenuEvent,
    # RunEvent::TrayIconEvent, RunEvent::ExitRequested, and
    # RunEvent::Exit, each before the run callback sees it. Mirrors the Plugin trait's
    # <tt>on_event(app, event)</tt> (plugin.rs).
    # Returns +nil+ by default.
    public def on_event(app, event)
      nil
    end

    # Called when the webview navigates to +url+, a Ferro::Url::Url, the
    # url crate's URL, as Tauri's hook takes a Url (plugin.rs:93-97).
    #
    # *Not yet called*: nothing in Tokra calls this hook, so no navigation
    # reaches it and its return value changes nothing. It is here for the
    # Plugin trait's shape. When it is wired, +true+ will allow the
    # navigation and +false+ will block it, as in Tauri. Tauri calls it
    # from the webview's navigation handler, which Tokra's webview
    # registers once plan 052e-4 ports it (plan 064, decision 9).
    # Returns +true+ by default.
    public def on_navigation(webview, url)
      true
    end

    # Called to handle IPC invoke commands.
    #
    # Return +true+ if this plugin handled the command, +false+ otherwise.
    # When +false+, the invoke is passed to the next handler in the chain.
    #
    # *Note*: Returning +false+ passes the invoke to subsequent handlers.
    # If no handler returns +true+, the invoke will remain unhandled.
    public def extend_api(invoke)
      false
    end

    # Returns JavaScript to inject at document start.
    #
    # Override this to inject custom JavaScript into the webview. App runs
    # it in every page after Tauri's own init scripts, wrapped in an IIFE
    # so its top-level names stay private (PluginStore#initialization_script).
    # A webview takes the scripts of the plugins registered when it is
    # made, as Tauri's does, so register the plugin with Builder#plugin
    # for the pages of the windows the config lists to run it.
    # Returns +nil+ by default (no script injection).
    public def initialization_script
      nil
    end

    # The #initialization_script with the frames it runs in, as
    # <tt>[script, for_main_frame_only]</tt>, or +nil+. By default the
    # script runs in the main frame only. Override it to run a script in
    # every frame, as Plugin::Builder#js_init_script_on_all_frames does.
    #
    # Mirrors the Plugin trait's +initialization_script_2+
    # (plugin.rs:73-83), Tauri's name until its version 3 renames it.
    #
    # === Example
    #
    #   def initialization_script_2
    #     ["window.__IN_EVERY_FRAME__ = true", false]
    #   end
    public def initialization_script_2
      script = initialization_script
      [script, true] if script
    end

    # Called when the app lets go of the plugin, and returns +nil+.
    #
    # Rust runs a type's +Drop+ when its last owner lets go. Ruby frees an
    # object when it chooses and tells nobody, so the plugin store calls
    # this at the moments Tauri's drops a plugin: when AppHandle#remove_plugin
    # removes it, when a plugin of the same name replaces it, and when
    # AppHandle#plugin fails to initialize it (plugin.rs:880-893;
    # app.rs:494-498). Does nothing by default.
    #
    # === Example
    #
    #   def drop
    #     @socket&.close
    #     nil
    #   end
    public def drop
      nil
    end

    # Called with each Tokra::Window the app makes, its config's included.
    #
    # Override this to perform window-specific setup. It runs on the main
    # thread, once the window has joined the app, so +get_window+ finds
    # it. A window made on another thread is built first, and then this
    # runs. Register the plugin with Builder#plugin to hear the config's
    # windows, which the app makes after it initializes the builder's
    # plugins and before its setup hook. Named without an +on_+ prefix to
    # mirror the Plugin trait's +window_created+ (plugin.rs:85-87,
    # manager/window.rs:112-121).
    # Returns +nil+ by default (no-op).
    public def window_created(window)
      nil
    end

    # Called with each Tokra::Webview the app makes, after
    # #window_created for its window.
    #
    # Override this to perform webview-specific setup. It runs on the main
    # thread, as #window_created does. Named without an +on_+ prefix to
    # mirror the Plugin trait's +webview_created+ (plugin.rs:89-91,
    # manager/webview.rs:603-614).
    # Returns +nil+ by default (no-op).
    public def webview_created(webview)
      nil
    end

    # Called when a webview starts or finishes loading a page.
    #
    # Override this to perform post-load setup or analytics. +webview+ is
    # the Tokra::Webview that loaded the page, and +payload+ a
    # PageLoadPayload with its URL and whether it started or finished. The
    # App calls it after Builder#on_page_load's block, for each plugin in
    # the order they were registered, as Tauri does (manager/webview.rs:282-300,
    # plugin.rs:965-972).
    # Returns +nil+ by default (no-op).
    public def on_page_load(webview, payload)
      nil
    end
  end

  # SPDX-SnippetBegin
  # SPDX-License-Identifier: Apache-2.0 OR MIT
  # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
  # SPDX-SnippetComment: PluginStore adapted from tauri/crates/tauri/src/plugin.rs

  # Routes IPC commands to registered plugins by name.
  #
  # A Tokra app hosts many plugins, each owning its own IPC commands.
  # Dispatching every command to every plugin would be slow, and one
  # plugin could shadow another's commands.
  #
  # This store keeps one plugin per name and routes each
  # <tt>plugin:NAME|command</tt> invoke to exactly one extend_api hook.
  # Mirrors Tauri's PluginStore (plugin.rs).
  #
  # === Example
  #
  #   store = Tokra::PluginStore.new
  #   store.register(MyPlugin.new(handle))
  #   store.extend_api("my-plugin", invoke)  #=> true when handled
  #
  class PluginStore
    # Creates an empty store.
    def initialize
      @store = []
      # The plugins #initialize_plugin has initialized, by identity.
      initialized = {} #: Hash[_Plugin, true]
      @initialized = initialized.compare_by_identity
    end

    # Adds a plugin to the store, replacing any same-named plugin, which
    # it drops (Plugin#drop).
    #
    # Returns +true+ if an existing plugin was replaced, +false+ otherwise.
    def register(plugin)
      replaced = take(plugin.name)
      @store.push(plugin)
      !replaced.empty?
    end

    # Removes the plugin with the given name from the store, and drops it
    # (Plugin#drop).
    #
    # Returns +true+ if a plugin was removed, +false+ otherwise.
    def unregister(name)
      !take(name).empty?
    end

    # Initializes +plugin+ with +app+ and its slice of +config+, the app
    # config's +plugins+ Hash: the value under the plugin's name, or +nil+.
    # A StandardError the plugin raises becomes
    # Error::PluginInitialization with the plugin's name and the error's
    # message. Returns +nil+.
    #
    # Mirrors Tauri's PluginStore#initialize and its +initialize+ function
    # (plugin.rs:895-903, 998-1010), named for Plugin#initialize_plugin.
    #
    # === Example
    #
    #   store.initialize_plugin(plugin, handle, handle.config.plugins)
    def initialize_plugin(plugin, app, config)
      begin
        plugin.initialize_plugin(app, config[plugin.name])
      rescue => e
        raise Error::PluginInitialization.new(plugin.name, e.message)
      end
      @initialized[plugin] = true
      nil
    end

    # Initializes every plugin in the store not yet initialized, in
    # store order, as #initialize_plugin does, stopping at the first that
    # fails. Returns +nil+.
    #
    # Tauri's initializes every plugin, and the core plugins it has
    # initialized already do nothing the second time; Tokra skips them
    # instead, which also keeps a plugin the app added between Builder#build
    # and App#run from initializing twice (plugin.rs:905-915; plan 064,
    # decision 5).
    #
    # === Example
    #
    #   store.initialize_all(handle, handle.config.plugins)
    def initialize_all(app, config)
      @store.each { |plugin| initialize_plugin(plugin, app, config) unless @initialized.key?(plugin) }
      nil
    end

    # Routes an invoke to the named plugin's extend_api hook.
    #
    # Returns whether the invoke was handled. The invoke is not handled
    # when the plugin exists *and* the command does not. When no plugin
    # has the given name, the invoke is rejected and +true+ is returned,
    # matching Tauri's PluginStore#extend_api.
    def extend_api(name, invoke)
      plugin = @store.find { |p| p.name == name }
      return plugin.extend_api(invoke) if plugin

      invoke.reject("plugin #{name} not found")
      true
    end

    # Collects every plugin's initialization script, in registration order,
    # each as <tt>[script, for_main_frame_only]</tt> (Plugin#initialization_script_2).
    #
    # Each script is wrapped as <tt>(function () { SCRIPT })();</tt> so its
    # top-level names stay private to the plugin. Plugins whose
    # initialization_script_2 returns +nil+ contribute nothing. Mirrors
    # Tauri's PluginStore#initialization_script (plugin.rs:918-933).
    #
    # === Example
    #
    #   store.initialization_script
    #   #=> [["(function () { console.log('ready') })();", true]]
    def initialization_script
      @store.filter_map do |plugin|
        pair = plugin.initialization_script_2
        next unless pair

        ["(function () { #{pair[0]} })();", pair[1]]
      end
    end

    # Dispatches a run event to every registered plugin.
    #
    # Plugins like the clipboard release native resources on
    # RunEvent::Exit; without this fan-out those hooks never fire.
    # Mirrors Tauri's PluginStore#on_event (plugin.rs).
    def on_event(app, event)
      @store.each { |plugin| plugin.on_event(app, event) }
    end

    # Tells every registered plugin, in registration order, that the app
    # made +window+, and returns +nil+.
    #
    # Mirrors Tauri's PluginStore#window_created (plugin.rs:935-942).
    #
    # === Example
    #
    #   store.window_created(app.get_window("main"))
    def window_created(window)
      @store.each { |plugin| plugin.window_created(window) }
      nil
    end

    # Tells every registered plugin, in registration order, that the app
    # made +webview+, and returns +nil+.
    #
    # Mirrors Tauri's PluginStore#webview_created (plugin.rs:944-950).
    #
    # === Example
    #
    #   store.webview_created(app.get_webview("main"))
    def webview_created(webview)
      @store.each { |plugin| plugin.webview_created(webview) }
      nil
    end

    # Tells every registered plugin, in registration order, that +webview+
    # started or finished loading a page, and returns +nil+.
    #
    # Mirrors Tauri's PluginStore#on_page_load (plugin.rs:965-972).
    #
    # === Example
    #
    #   store.on_page_load(webview, Tokra::PageLoadPayload.new(url: "tokra://localhost/", started: false))
    def on_page_load(webview, payload)
      @store.each { |plugin| plugin.on_page_load(webview, payload) }
      nil
    end

    # Removes the plugins named +name+ and drops each, as Rust's +retain+
    # drops what it removes. Answers what it removed.
    private def take(name)
      taken, @store = @store.partition { |plugin| plugin.name == name }
      taken.each do |plugin|
        @initialized.delete(plugin)
        plugin.drop
      end
      taken
    end
  end

  # SPDX-SnippetEnd
end
