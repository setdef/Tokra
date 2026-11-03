# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "uri"
require_relative "support/stub_native"
require_relative "support/test_app"

# WebviewWindowBuilder makes a window and its webview at run time, as
# Tauri's does (plan 052, phase 2): the labels checked in Tauri's order and
# words, the pair joined to the app at once, the native creation on the
# main thread, at once there and queued from anywhere else, and the
# plugins and the page told in Tauri's order (window/mod.rs:328-427;
# manager/window.rs:61-124; manager/webview.rs:401-636; tauri-runtime-wry
# lib.rs:234-254, 299-362, 3912-3943).
#
# StubNative's loop delivers the TaskEvents a test injects, each running
# one queued task, so every order below is read from a log, never a clock.
class TestWebviewWindowBuilder < Minitest::Test
  # Logs each created hook, by the label it is given.
  class CreatedPlugin < Tokra::Plugin
    def initialize(app, log)
      super(app)
      @log = log
    end

    def name = "created"
    def window_created(window) = @log << [:window_created, window.label]
    def webview_created(webview) = @log << [:webview_created, webview.label]
  end

  INVALID = Tokra::Error::Runtime::INVALID_WINDOW_LABEL

  def app_url
    (Tokra::App.os_name == "windows") ? "http://tokra.localhost/" : "tokra://localhost/"
  end

  def page(path = "index.html") = Tokra::WebviewUrl::App.new(path)
  def url(text) = Ferro::Url::Url.parse(text)

  # Runs an app whose Ready handler, on the main thread, gets the handle
  # and the log; +tasks+ TaskEvents follow, each running one queued task.
  # Ruby listeners and the created plugin log into the same Array.
  def run_app(tasks: 0, &on_ready)
    log = []
    app = build_test_app
    app.handle.plugin(CreatedPlugin.new(app.handle, log))
    %w[tauri://webview-created tauri://window-created].each do |name|
      app.handle.listen_any(name) { |event| log << [:heard, name, event.payload] }
    end
    StubNative.inject_event(Array.new(tasks) { Tokra::Native::TaskEvent.new })
    app.run { |handle, event| on_ready&.call(handle, log) if event.is_a?(Tokra::RunEvent::Ready) }
    log
  end

  def native_webview(label) = StubNative::WebView.instances.find { |webview| webview.label == label }

  def test_a_label_with_a_character_tauri_refuses_raises_its_runtime_error
    errors = {}
    run_app do |handle|
      ["a b", "a.b", "a\0b", "caf\xC3".b.force_encoding(Encoding::UTF_8), "😀"].each do |label|
        errors[label] = assert_raises(Tokra::Error::Runtime) { Tokra::WebviewWindowBuilder.new(handle, label, page).build }
      end
    end

    errors.each do |label, error|
      assert_equal "runtime error: #{INVALID}", error.message, label.inspect
    end
    assert_equal "Window labels must only include alphanumeric characters, `-`, `/`, `:` and `_`.", INVALID
  end

  def test_unicode_letters_and_digits_and_the_empty_label_pass
    run_app do |handle|
      ["é", "日本", "٣", "Ⅻ", "a-b/c:d_e", ""].each do |label|
        Tokra::WebviewWindowBuilder.new(handle, label, page).build
      end
    end

    assert_equal ["main", "é", "日本", "٣", "Ⅻ", "a-b/c:d_e", ""], StubNative.windows.map(&:label)
  end

  def test_a_label_that_is_not_a_string_raises_type_error
    run_app do |handle|
      assert_raises(TypeError) { Tokra::WebviewWindowBuilder.new(handle, :side, page) }
    end
  end

  def test_the_webviews_label_is_checked_before_the_windows
    errors = {}
    run_app do |handle|
      handle.windows["only-window"] = Tokra::Window.new(label: "only-window", native: StubNative::Window.new(nil, "x"),
        app_handle: handle)
      handle.webviews["only-webview"] = Tokra::Webview.new(label: "only-webview",
        native: StubNative::WebView.new([]), window: handle.get_window("main"), app_handle: handle)
      %w[main only-window only-webview].each do |label|
        errors[label] = assert_raises(Tokra::Error) { Tokra::WebviewWindowBuilder.new(handle, label, page).build }
      end
    end

    assert_instance_of Tokra::Error::WebviewLabelAlreadyExists, errors["main"], "the webview's check comes first"
    assert_equal "a webview with label `main` already exists", errors["main"].message
    assert_equal "a webview with label `only-webview` already exists", errors["only-webview"].message
    assert_instance_of Tokra::Error::WindowLabelAlreadyExists, errors["only-window"]
    assert_equal "a window with label `only-window` already exists", errors["only-window"].message
    assert_equal "only-window", errors["only-window"].label
  end

  def test_a_refused_label_builds_nothing_and_tells_no_one
    log = run_app do |handle, recorded|
      recorded.clear
      assert_raises(Tokra::Error) { Tokra::WebviewWindowBuilder.new(handle, "main", page).build }
    end

    assert_empty log
    assert_equal ["main"], StubNative.windows.map(&:label)
  end

  # An App path the url crate's join refuses raises Error::InvalidUrl on
  # the calling thread, before anything is built (plan 055, decision 7).
  def test_an_app_path_the_join_refuses_raises_invalid_url_and_builds_nothing
    log = run_app do |handle, recorded|
      recorded.clear
      assert_raises(Tokra::Error::InvalidUrl) { Tokra::WebviewWindowBuilder.new(handle, "side", page("//exa mple")).build }
    end

    assert_empty log
    assert_equal ["main"], StubNative.windows.map(&:label)
  end

  def test_on_the_main_thread_the_window_exists_when_build_returns
    built = nil
    run_app do |handle|
      built = Tokra::WebviewWindowBuilder.new(handle, "side", page("side.html")).title("Side").inner_size(320, 240)
        .build
      native = built.window.native
      assert native.opened?, "the native window was not built before build returned"
      assert_equal ["side", "Side", [320.0, 240.0], Thread.current], [native.label, native.title, native.size, native.opened_on]
      assert native_webview("side").opened?, "the native webview was not built before build returned"
    end

    assert_equal "#{app_url}side.html", native_webview("side").url
    assert_same built.window.native, native_webview("side").window
    assert_same built.window, built.webview.window
    assert_includes native_webview("side").initialization_scripts[2], 'currentWindow: { label: "side" }'
  end

  def test_main_is_built_through_the_builder_with_the_app_url
    run_app

    main = StubNative.windows.first
    assert_equal ["main", "Tokra", [800.0, 600.0]], [main.label, main.title, main.size]
    assert_equal app_url, native_webview("main").url
  end

  def test_plugins_hear_the_window_then_the_webview_and_the_page_hears_webview_created_first
    log = run_app do |handle, recorded|
      main = handle.get_webview("main")
      main.listen_js("tauri://window-created", Tokra::EventTarget.any, 1)
      main.listen_js("tauri://webview-created", Tokra::EventTarget.any, 2)
      main.native.evals.clear
      recorded.clear
      Tokra::WebviewWindowBuilder.new(handle, "side", page).build
    end

    assert_equal [
      [:window_created, "side"],
      [:webview_created, "side"],
      [:heard, "tauri://webview-created", '{"label":"side"}'],
      [:heard, "tauri://window-created", '{"label":"side"}'],
    ], log
    page_heard = native_webview("main").evals.map { |script| script[%r{tauri://[a-z-]+}] }
    assert_equal ["tauri://webview-created", "tauri://window-created"], page_heard
  end

  def test_plugins_registered_before_the_run_hear_main_built
    log = run_app
    assert_equal [[:window_created, "main"], [:webview_created, "main"]], log.first(2)
  end

  # From another thread, build returns before anything native happens;
  # the queued creation runs first, then the hooks, the events, and the
  # title the thread set at once.
  def test_from_another_thread_the_creation_is_queued_ahead_of_later_calls
    built = nil
    log = run_app(tasks: 8) do |handle, recorded|
      recorded.clear
      built = Thread.new do
        webview_window = Tokra::WebviewWindowBuilder.new(handle, "side", page).build
        recorded << [:returned, webview_window.window.native.opened?, webview_window.webview.native.opened?]
        webview_window.set_title("set at once")
        webview_window
      end.value
      recorded << [:joined]
      native = built.window.native
      native.define_singleton_method(:set_title) do |title|
        recorded << [:set_title, title]
        super(title)
      end
      native.define_singleton_method(:open) do |*args|
        recorded << [:open]
        super(*args)
      end
    end

    assert_equal [
      [:heard, "tauri://webview-created", '{"label":"side"}'],
      [:returned, false, false],
      [:joined],
      [:open],
      [:window_created, "side"],
      [:webview_created, "side"],
      [:heard, "tauri://window-created", '{"label":"side"}'],
      [:set_title, "set at once"],
    ], log
    assert_equal "set at once", built.window.native.title
    assert_equal Thread.current, built.window.native.opened_on, "the window was built off the main thread"
  end

  def test_a_failed_native_creation_is_warned_not_raised
    built = nil
    assert_output(nil, "failed to create window\n") do
      run_app do |handle|
        StubNative.fail_next_open = "no window for you"
        built = Tokra::WebviewWindowBuilder.new(handle, "side", page).build
      end
    end

    refute built.window.native.opened?
    refute built.webview.native.opened?, "the webview was built in a window that failed"
    assert_equal %w[main side], built.app_handle.windows.keys, "the window stays in the app, as Tauri's does"
    assert_nil built.window.native.title, "an empty window answers as a closed one"
  end

  # Tauri decides the last window closed from its runtime's store, which a
  # window whose creation failed never joins (tauri-runtime-wry
  # lib.rs:3934-3943, 4171-4185).
  def test_a_window_that_failed_does_not_keep_the_app_from_exiting
    events = []
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new("main"))
    assert_output(nil, /failed to create window/) do
      run_test_app do |handle, event|
        events << event.class
        if event.is_a?(Tokra::RunEvent::Ready)
          StubNative.fail_next_open = "no window for you"
          Tokra::WebviewWindowBuilder.new(handle, "side", page).build
        end
      end
    end

    assert_includes events, Tokra::RunEvent::ExitRequested
    assert_equal 0, StubNative.exit_code
  end

  # Tauri asks to exit only when a Destroyed removes a window from its
  # store and the store is then empty (tauri-runtime-wry lib.rs:4171-4185);
  # a window the store never held, here one built by hand, asks nothing,
  # even once the store is empty.
  def test_a_window_outside_the_store_does_not_ask_to_exit_again
    asked = 0
    StubNative.inject_event([Tokra::Native::WindowCloseEvent.new("main"), Tokra::Native::WindowCloseEvent.new("frame")])
    run_test_app do |handle, event|
      case event
      when Tokra::RunEvent::Ready
        native = StubNative::Window.new(handle.runtime_context.window_target, "frame")
        handle.windows["frame"] = Tokra::Window.new(label: "frame", native:, app_handle: handle)
      when Tokra::RunEvent::ExitRequested
        asked += 1
        event.api.prevent_exit
      end
    end

    assert_equal 1, asked, "only main's Destroyed emptied the store"
  end

  # Tauri's create_window returns the webview's error before it inserts the
  # window, which drops (tauri-runtime-wry lib.rs:4489-4500); the window's
  # Destroyed then names an id the runtime never held.
  def test_a_window_whose_webview_failed_is_discarded_without_a_destroyed
    built = nil
    events = []
    StubNative.inject_event(Tokra::Native::WindowCloseEvent.new("main"))
    assert_output(nil, "failed to create webview: no webview for you\n") do
      run_test_app do |handle, event|
        events << [event.class, (event.label if event.respond_to?(:label))]
        if event.is_a?(Tokra::RunEvent::Ready)
          StubNative.fail_next_webview_open = "no webview for you"
          built = Tokra::WebviewWindowBuilder.new(handle, "side", page).build
        end
      end
    end

    assert built.window.native.discarded?, "the window outlived its webview's failure"
    refute built.webview.native.opened?
    refute_includes events, [Tokra::RunEvent::WindowEvent, "side"], "the discarded window reached Ruby"
    assert_includes events, [Tokra::RunEvent::ExitRequested, nil], "it holds the app open"
  end

  def test_build_before_the_app_runs_raises_runtime_error
    app = build_test_app
    error = assert_raises(Tokra::Error::Runtime) { Tokra::WebviewWindowBuilder.new(app, "early", page).build }

    assert_equal "runtime error: the event loop does not exist yet", error.message
    assert_empty app.windows
  end

  def test_the_setup_hook_finds_main_built
    hook = Ractor.shareable_proc { |app| Thread.current[:found_main] = app.get_webview_window("main") }
    run_test_app(Tokra::Builder.default.setup(&hook))
    found = Thread.current[:found_main]

    assert_instance_of Tokra::WebviewWindow, found
    assert found.window.native.opened?, "main was not built before the hook"
  ensure
    Thread.current[:found_main] = nil
  end

  def test_app_urls_join_the_app_url_and_others_load_as_given
    manager = Tokra::AppManager.new(config: Tokra::Config.new(identifier: nil, product_name: nil, version: nil),
      webviews: {}, windows: {})
    webviews = Tokra::WebviewManager.new(manager, os_name: Tokra::App.os_name)

    assert_equal app_url, webviews.webview_url(page("index.html"))
    assert_equal "#{app_url}users/john", webviews.webview_url(page("users/john"))
    assert_equal "#{app_url}a%20b.html", webviews.webview_url(page(Pathname("a b.html")))
    # The url crate's join keeps a fragment, a query, and an escape, and
    # encodes its path set (manager/webview.rs:418-430).
    assert_equal "#{app_url}page.html#intro", webviews.webview_url(page("page.html#intro"))
    assert_equal "#{app_url}find?q=1", webviews.webview_url(page("find?q=1"))
    assert_equal "#{app_url}a%20b.html", webviews.webview_url(page("a%20b.html"))
    assert_equal "#{app_url}%22%3C%3E%60%7B%7D%C3%A9.html", webviews.webview_url(page(%("<>`{}é.html)))
    assert_equal "#{app_url}find?q=a%20b#x%20y", webviews.webview_url(page("find?q=a b#x y"))
    # The url crate's join keeps what Ruby's URI refuses, and never fails
    # (manager/webview.rs:418-430: "this will never fail").
    assert_equal "#{app_url}a|b.html", webviews.webview_url(page("a|b.html"))
    assert_equal "#{app_url}a^b.html", webviews.webview_url(page("a^b.html"))
    assert_equal "#{app_url}a#b#c", webviews.webview_url(page("a#b#c"))
    assert_equal "#{app_url}a%zz.html", webviews.webview_url(page("a%zz.html"))
    assert_equal "#{app_url}a#%60", webviews.webview_url(page("a#`")), "a fragment's ` is encoded, not refused"
    assert_equal "#{app_url}find?q={}", webviews.webview_url(page("find?q={}")), "the url crate keeps a query's braces"
    # The url crate strips tab and newlines anywhere, and C0 controls and
    # space at either end (url 2.5.8 src/parser.rs:225-245, 284-297).
    assert_equal "#{app_url}ab.html", webviews.webview_url(page("a\tb.html"))
    assert_equal "#{app_url}ab.html", webviews.webview_url(page("a\nb\r.html"))
    assert_equal "#{app_url}a.html", webviews.webview_url(page(" a.html "))
    assert_equal "#{app_url}a.html", webviews.webview_url(page("\u0001a.html\u001F"))
    assert_equal "https://tauri.app/", webviews.webview_url(Tokra::WebviewUrl::External.new(url("https://tauri.app/")))
    assert_equal "doom://index.html", webviews.webview_url(Tokra::WebviewUrl::CustomProtocol.new(url("doom://index.html")))
    data = "data:text/html,<p>hi</p>"
    assert_equal data, webviews.webview_url(Tokra::WebviewUrl::CustomProtocol.new(url(data)))
    # Tauri maps a failed join to Error::InvalidUrl, then unwraps it
    # (manager/webview.rs:423-427); here it raises.
    # The words are the url crate's, and depend on the app URL's scheme: an
    # http host (Windows) goes through IDNA, a tokra:// host does not.
    {
      "windows" => "invalid url: invalid international domain name",
      "macos" => "invalid url: invalid domain character",
    }.each do |os_name, message|
      on = Tokra::WebviewManager.new(manager, os_name:)
      error = assert_raises(Tokra::Error::InvalidUrl) { on.webview_url(page("//exa mple")) }
      assert_equal message, error.message, os_name
    end
  end

  # An http app URL is special, so the url crate reads a path's \\ as /
  # (url 2.5.8 src/parser.rs:912); Tokra's is http on Windows.
  def test_on_windows_a_backslash_in_an_app_path_is_a_slash
    manager = Tokra::AppManager.new(config: Tokra::Config.new(identifier: nil, product_name: nil, version: nil),
      webviews: {}, windows: {})
    windows = Tokra::WebviewManager.new(manager, os_name: "windows")
    macos = Tokra::WebviewManager.new(manager, os_name: "macos")

    assert_equal "http://tokra.localhost/a/b", windows.webview_url(page("a\\b"))
    assert_equal "tokra://localhost/a\\b", macos.webview_url(page("a\\b")), "tokra:// is not special, so \\ stays"
  end

  def test_webview_urls_refuse_the_wrong_types
    assert_raises(TypeError) { Tokra::WebviewUrl::App.new(:index) }
    assert_raises(TypeError) { Tokra::WebviewUrl::External.new("https://tauri.app") }
    assert_raises(TypeError) { Tokra::WebviewUrl::CustomProtocol.new("doom://index.html") }
    assert_equal Pathname("index.html"), page.path
  end

  # Tauri's External and CustomProtocol hold the url crate's Url
  # (config.rs:72-125), so Ruby's URI is refused, not converted (plan 055,
  # decision 1).
  def test_external_and_custom_protocol_take_only_the_url_crates_url
    error = assert_raises(TypeError) { Tokra::WebviewUrl::External.new(URI("https://tauri.app/")) }
    assert_equal "wrong argument type URI::HTTPS (expected Ferro::Url::Url)", error.message
    error = assert_raises(TypeError) { Tokra::WebviewUrl::CustomProtocol.new(URI("doom://index.html")) }
    assert_equal "wrong argument type URI::Generic (expected Ferro::Url::Url)", error.message
  end

  # Rust moves the Url into the enum; a Ruby value holds a frozen one, so
  # the caller's later change does not reach it (plan 055, decision 3).
  def test_a_webview_url_holds_a_frozen_copy_of_its_url
    given = url("https://tauri.app/")
    external = Tokra::WebviewUrl::External.new(given)
    given.set_path("/changed")

    assert_predicate external.url, :frozen?
    assert_equal "https://tauri.app/", external.url.as_str
    frozen = url("doom://index.html").freeze
    assert_same frozen, Tokra::WebviewUrl::CustomProtocol.new(frozen).url
  end
end
