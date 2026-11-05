# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"
require_relative "support/stub_native"
require_relative "support/test_app"

# Where a webview keeps its data, and the scheme its pages are served
# over (plan 052, 052e-3): the data_directory and use_https_scheme rows
# reach the native webview (webview/mod.rs:968-974, 1108-1111), a webview
# with no directory gets <local data>/<identifier> on Linux and Windows,
# made if missing (manager/webview.rs:505-523), and a webview built with
# https gets https://tokra.localhost/ and core.js's https scheme on
# Windows (manager/webview.rs:385, 416; manager/mod.rs:331-338), whose
# origin the app takes as its own (webview/mod.rs:1680-1688).
class TestWebviewDataDirectory < Minitest::Test
  WINDOWS = Tokra::App.os_name == "windows"

  def setup
    @dir = Dir.mktmpdir("tokra-data-directory")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def page = Tokra::WebviewUrl::App.new("index.html")

  # A WebviewManager on +os_name+ whose local data directory is +local+.
  def manager(os_name, local: @dir)
    Tokra::WebviewManager.new(build_test_manager, os_name:, data_local_dir: -> { local })
  end

  # Runs an app and calls the block on the main thread once it is Ready.
  def run_app(&on_ready)
    build_test_app.run { |handle, event| on_ready&.call(handle) if event.is_a?(Tokra::RunEvent::Ready) }
  end

  # Builds the webview window "side" with +rows+ applied, and answers its
  # native webview.
  def build_side(&rows)
    native = nil
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.new(handle, "side", page)
      returned = rows ? rows.call(builder) : builder
      assert_same builder, returned, "a row answers the builder"
      native = builder.build.webview.native
    end
    native
  end

  # Rust's display of +path+ pushed onto +base+.
  def rust_join(base, path) = "#{base}#{File::ALT_SEPARATOR || '/'}#{path}"

  # --- data_directory ---

  def test_a_data_directory_reaches_the_webview_as_a_path_and_is_made
    directory = File.join(@dir, "profiles", "side")
    native = build_side { |builder| builder.data_directory(Pathname(directory)) }

    assert_equal directory, native.attributes[:data_directory]
    assert File.directory?(directory), "the directory and its parents are made"
  end

  def test_a_data_directory_that_exists_is_used_as_it_is
    marker = File.join(@dir, "kept")
    File.write(marker, "")
    native = build_side { |builder| builder.data_directory(@dir) }

    assert_equal @dir, native.attributes[:data_directory]
    assert File.exist?(marker)
  end

  def test_a_data_directory_must_be_a_path
    run_app do |handle|
      builder = Tokra::WebviewWindowBuilder.new(handle, "side", page)
      assert_raises(TypeError) { builder.data_directory(42) }
    end
  end

  # The directory is made where prepare_webview makes it, before the
  # window is built; std's error is Error::Io, Windows' codes included
  # (error.rs:53-54).
  def test_a_data_directory_that_cannot_be_made_raises_io_and_builds_nothing
    file = File.join(@dir, "file")
    File.write(file, "")
    blocked = File.join(file, "side")
    std = assert_raises(RuntimeError) { Tokra::Native.fs_create_dir_all(blocked) }.message
    error = nil
    labels = nil
    run_app do |handle|
      error = assert_raises(Tokra::Error::Io) do
        Tokra::WebviewWindowBuilder.new(handle, "side", page).data_directory(blocked).build
      end
      labels = [handle.webviews.key?("side"), handle.windows.key?("side")]
    end

    assert_equal std, error.message
    assert_match(/\(os error \d+\)\z/, error.message)
    assert_equal [false, false], labels, "neither the webview nor the window joined the app"
    assert_equal ["main"], StubNative.webviews.map(&:label), "no native webview was opened"
  end

  def test_a_webview_with_no_directory_gets_the_apps_on_linux_and_windows
    expected = rust_join(@dir, TestApp::IDENTIFIER)
    directories = %w[linux windows macos].to_h { |os_name| [os_name, manager(os_name).data_directory(nil)] }

    assert_equal({ "linux" => expected, "windows" => expected, "macos" => nil }, directories)
    assert File.directory?(expected), "the app's directory is made"
  end

  def test_with_no_local_data_directory_a_webview_gets_none
    assert_nil manager("linux", local: nil).data_directory(nil)
  end

  def test_a_named_directory_is_kept_and_made_on_every_platform
    %w[linux windows macos].each do |os_name|
      directory = File.join(@dir, os_name)
      assert_equal directory, manager(os_name).data_directory(directory), os_name
      assert File.directory?(directory), os_name
    end
  end

  # Rust's PathBuf::push: an absolute path stands alone, and a base that
  # ends with a separator takes no other.
  def test_the_app_directory_is_pushed_as_rust_pushes_a_path
    separator = File::ALT_SEPARATOR || "/"

    assert_equal "base#{separator}id", Tokra::WebviewManager.push("base", "id")
    assert_equal "base/id", Tokra::WebviewManager.push("base/", "id")
    assert_equal @dir, Tokra::WebviewManager.push("base", @dir)
  end

  def test_the_webview_of_a_built_window_gets_the_apps_directory_on_linux_and_windows
    assert_equal [TestApp.default_data_directory], [build_side.attributes[:data_directory]]
  end

  # The app reads the local data directory from the native module it runs
  # on, so a stub app's webviews keep their data in StubNative's temporary
  # directory, and no test writes to the user's own.
  def test_the_local_data_directory_comes_from_the_native_module_the_app_runs_on
    stub = StubNative.data_local_dir
    directories = %w[linux windows].map do |os_name|
      context = Tokra::RuntimeContext.new(native: StubNative)
      Tokra::AppHandle.new(build_test_manager, runtime_context: context, os_name:).webview_manager.data_directory(nil)
    end

    assert_equal [rust_join(stub, TestApp::IDENTIFIER)] * 2, directories
    assert File.directory?(directories.first), "the app's directory is made in the stub's"
    assert stub.start_with?(File.join(Dir.tmpdir, "")), "the stub's directory is a temporary one"
  end

  # As in Tauri, the webview is prepared, its directory made, before the
  # window's label is checked: WebviewWindowBuilder::build prepares the
  # webview in with_webview (webview/mod.rs:700-783; manager/webview.rs:
  # 505-523) before build_internal's prepare_window refuses the label
  # (window/mod.rs:333-361; manager/window.rs:61-77). A webview's label is
  # refused first, before anything is made.
  def test_the_directory_is_made_before_the_windows_label_is_refused_but_not_the_webviews
    window_directory = File.join(@dir, "window")
    webview_directory = File.join(@dir, "webview")
    errors = run_app_collecting do |handle|
      handle.windows["only-window"] = Tokra::Window.new(label: "only-window", native: StubNative::Window.new(nil, "x"),
        app_handle: handle)
      {
        "only-window" => window_directory,
        "main" => webview_directory,
      }.to_h do |label, directory|
        builder = Tokra::WebviewWindowBuilder.new(handle, label, page).data_directory(directory)
        [label, assert_raises(Tokra::Error) { builder.build }.class]
      end
    end

    assert_equal({
"only-window" => Tokra::Error::WindowLabelAlreadyExists,
"main" => Tokra::Error::WebviewLabelAlreadyExists,
}, errors)
    assert File.directory?(window_directory), "prepare_webview made it before prepare_window refused the label"
    refute File.exist?(webview_directory), "the webview's label is refused before its directory is made"
  end

  # Runs an app and answers what the block answers on the main thread once
  # it is Ready.
  private def run_app_collecting
    result = nil
    run_app { |handle| result = yield(handle) }
    result
  end

  # --- use_https_scheme ---

  def test_use_https_scheme_reaches_the_webview_by_ruby_truthiness
    assert_equal [true, false], [
      build_side { |builder| builder.use_https_scheme("yes") }.attributes[:use_https_scheme],
      build_side { |builder| builder.use_https_scheme(nil) }.attributes[:use_https_scheme],
    ]
  end

  def test_on_windows_https_serves_the_app_from_https_tokra_localhost
    assert_equal "https://tokra.localhost/side.html", manager("windows").webview_url(page_at("side.html"), https: true)
    assert_equal "http://tokra.localhost/side.html", manager("windows").webview_url(page_at("side.html"))
    %w[macos linux].each do |os_name|
      assert_equal "tokra://localhost/side.html", manager(os_name).webview_url(page_at("side.html"), https: true)
    end
  end

  def test_https_is_core_js_protocol_scheme
    core = -> (https) { manager("windows").initialization_scripts("side", "side", https:)[3] }

    assert_includes core.call(true), 'const protocolScheme = "https"'
    assert_includes core.call(false), 'const protocolScheme = "http"'
  end

  def test_a_built_webview_loads_and_scripts_its_scheme
    https = build_side { |builder| builder.use_https_scheme(true) }
    http = build_side

    assert_equal(WINDOWS ? "https://tokra.localhost/" : "tokra://localhost/", https.url)
    assert_equal(WINDOWS ? "http://tokra.localhost/" : "tokra://localhost/", http.url)
    assert(https.initialization_scripts.any? { |script| script.include?('const protocolScheme = "https"') })
    assert(http.initialization_scripts.any? { |script| script.include?('const protocolScheme = "http"') })
  end

  # is_local_url compares the origin with tauri_protocol_url for the
  # origin's own scheme (webview/mod.rs:1680-1688): on Windows both
  # http://tokra.localhost and https://tokra.localhost are the app's.
  def test_on_windows_an_https_origin_of_the_app_is_local
    results = %w[windows macos].to_h do |os_name|
      origins = ["https://tokra.localhost/", "http://tokra.localhost/", "https://elsewhere.localhost/"]
      [os_name, origins.map { |origin| local?(os_name, origin) }]
    end

    assert_equal({ "windows" => [true, true, false], "macos" => [false, false, false] }, results)
  end

  private def local?(os_name, origin)
    app = build_test_app
    app.stub(:os_name, os_name) { app.__send__(:local_url?, origin) }
  end

  private def page_at(path) = Tokra::WebviewUrl::App.new(path)
end
