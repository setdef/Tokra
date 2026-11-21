# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../support/stub_native"
require_relative "../support/test_app"

# The path core plugin, which answers @tauri-apps/api/path
# (path/plugin.rs, packages/api/src/path.ts). Each command's body is
# checked on Unix and on Windows by Rust's rules; the invokes go through
# a real app's plugin store on the host.
class TestPathPlugin < Minitest::Test
  P = Tokra::Path::Plugin
  UNIX = Tokra::Path::Std::UNIX
  WINDOWS = Tokra::Path::Std::WINDOWS
  INIT_JS = File.expand_path("../../vendor/tauri/crates/tauri/src/path/init.js", __dir__)

  def setup
    @app = build_test_app
    @handle = @app.handle
    window = Tokra::Window.new(label: "main", native: StubNative::Window.new(nil, "main"), app_handle: @handle)
    @webview = Tokra::Webview.new(label: "main", native: StubNative::WebView.new, window:, app_handle: @handle)
  end

  # Tauri's own test of basename (plugin.rs:257-289).
  def test_tauris_basename_cases
    path = "/path/to/some-json-file.json"

    assert_equal "some-json-file", P.basename(UNIX, path, ".json")
    assert_equal "some-json-file.", P.basename(UNIX, path, "json")
    assert_equal "some-json-file.html", P.basename(UNIX, "/path/to/some-json-file.html.json", ".json")
    assert_equal "some-json-file.json", P.basename(UNIX, "/path/to/some-json-file.json.json", ".json")
    assert_equal "some-json-file.json.html", P.basename(UNIX, "/path/to/some-json-file.json.html", ".json")
  end

  def test_basename_without_an_extension_and_without_a_name
    assert_equal "b.txt", P.basename(UNIX, "a/b.txt", nil)
    assert_equal "b", P.basename(WINDOWS, "C:\\a\\b", nil)
    assert_raises(Tokra::Error::NoBasename) { P.basename(UNIX, "/", nil) }
    assert_raises(Tokra::Error::NoBasename) { P.basename(UNIX, "a/..", nil) }
  end

  # Tauri's own test of join (plugin.rs:291-312), each case on both
  # families.
  def test_tauris_join_cases
    [
      [[""], ".", "."],
      [["", ""], ".", "."],
      [["a"], "a", "a"],
      [["", "a"], "a", "a"],
      [["a", "b"], "a/b", "a\\b"],
      [["a", "", "b"], "a/b", "a\\b"],
      [["a", "/b", "c"], "a/b/c", "a\\b\\c"],
      [["a", "b/c", "d"], "a/b/c/d", "a\\b\\c\\d"],
      [["a/", "b"], "a/b", "a\\b"],
    ].each do |paths, unix, windows|
      assert_equal unix, P.join(UNIX, paths), paths.inspect
      assert_equal windows, P.join(WINDOWS, paths), paths.inspect
    end
  end

  def test_join_resolves_parents_and_keeps_an_absolute_start
    assert_equal "/a/c", P.join(UNIX, ["/a", "b", "../c"])
    assert_equal "C:\\a\\c", P.join(WINDOWS, ["C:\\a", "b", "..\\c"])
    assert_equal ".", P.join(UNIX, [])
  end

  # normalize keeps Node's answers for ".." and "." and a trailing
  # separator (plugin.rs:113-132), and otherwise what Tauri's code
  # computes, "" for "" among them, and "//" for "/", since its check
  # for a trailing separator is always true.
  def test_normalize_as_tauri_computes
    {
      ".." => "..",
      "." => ".",
      "" => "",
      "/" => "//",
      "/a/b/../c/./d/" => "/a/c/d/",
      "a/../.." => "",
      "../a" => "a",
      "a//b" => "a/b",
    }.each { |path, normalized| assert_equal normalized, P.normalize(UNIX, path), path.inspect }
  end

  def test_normalize_on_windows
    {
      "C:\\a\\..\\b" => "C:\\b",
      "C:/a/./b/" => "C:\\a\\b\\",
      "\\\\?\\C:\\a\\.\\b" => "C:\\a\\b",
      "a/b" => "a\\b",
    }.each { |path, normalized| assert_equal normalized, P.normalize(WINDOWS, path), path.inspect }
  end

  # resolve starts at the current directory and pushes each path, so an
  # absolute one starts over (plugin.rs:98-111).
  def test_resolve_from_the_current_directory
    assert_equal "/home/u/w", P.resolve(UNIX, [], "/home/u/w")
    assert_equal "/home/u/w", P.resolve(UNIX, ["."], "/home/u/w")
    assert_equal "/home/u/b", P.resolve(UNIX, ["../b"], "/home/u/w")
    assert_equal "/tmp/file/baz", P.resolve(UNIX, ["/foo/bar", "/tmp/file", "baz"], "/home/u/w")
    assert_equal "D:\\y", P.resolve(WINDOWS, ["x", "D:\\y"], "C:\\w")
    assert_equal "C:\\w\\x", P.resolve(WINDOWS, ["x"], "C:\\w")
  end

  def test_dirname
    assert_equal "/a", P.dirname(UNIX, "/a/b")
    assert_equal "", P.dirname(UNIX, "a")
    assert_equal "C:\\", P.dirname(WINDOWS, "C:\\a")
    error = assert_raises(Tokra::Error::NoParent) { P.dirname(UNIX, "/") }
    assert_equal "path does not have a parent", error.message
    assert_raises(Tokra::Error::NoParent) { P.dirname(UNIX, "") }
    assert_raises(Tokra::Error::NoParent) { P.dirname(WINDOWS, "C:\\") }
  end

  def test_extname
    assert_equal "json", P.extname(UNIX, "a/b.json")
    assert_equal "gz", P.extname(UNIX, "a.tar.gz")
    assert_equal "txt", P.extname(WINDOWS, "C:\\a\\b.txt")
    ["a/b", ".bashrc", "a/..", "/"].each do |path|
      error = assert_raises(Tokra::Error::NoExtension, path) { P.extname(UNIX, path) }
      assert_equal "path does not have an extension", error.message
    end
  end

  def test_is_absolute
    assert P.is_absolute(UNIX, "/a")
    refute P.is_absolute(UNIX, "a")
    assert P.is_absolute(WINDOWS, "C:\\a")
    assert P.is_absolute(WINDOWS, "\\\\server\\share\\a")
    refute P.is_absolute(WINDOWS, "\\a")
    refute P.is_absolute(WINDOWS, "C:a")
  end

  # Tauri registers path first of its core plugins (app.rs:1122-1135).
  def test_the_plugin_is_the_first_core_plugin
    assert_equal "path", @handle.manager.plugins.instance_variable_get(:@store).first.name
  end

  # init.js, rendered as serialize_to_javascript renders a template
  # value: JSON inside JSON.parse('...'), its backslashes and quotes
  # escaped (plugin.rs:204-221; serialize-to-javascript 0.1.2 lib.rs:188-238).
  def test_the_init_script_is_tauris_with_the_separator_and_delimiter
    template = File.read(INIT_JS)
    unix = P.new(@handle, target: Tokra::Utils::Platform::Target::Linux).initialization_script
    windows = P.new(@handle, target: Tokra::Utils::Platform::Target::Windows).initialization_script

    assert_equal template.sub("__TEMPLATE_sep__", %q{JSON.parse('"/"')})
      .sub("__TEMPLATE_delimiter__", %q{JSON.parse('":"')}), unix
    assert_equal template.sub("__TEMPLATE_sep__", %q{JSON.parse('"\\\\\\\\"')})
      .sub("__TEMPLATE_delimiter__", %q{JSON.parse('";"')}), windows
  end

  # The host's plugin answers by the host's rules: Rust's PathBuf joins
  # with a backslash on Windows, and there "/a" has no prefix, so it is
  # not absolute.
  private def windows_host? = Tokra::Utils::Platform::Target.current == Tokra::Utils::Platform::Target::Windows

  private def host_separator = windows_host? ? "\\" : "/"

  def test_resolve_directory_answers_a_base_directory_and_path
    home = Tokra::Native.home_dir

    assert_equal [true, JSON.generate(home)], invoke("resolve_directory", { "directory" => 21 })
    assert_equal [true, JSON.generate("#{home}#{host_separator}a")],
      invoke("resolve_directory", { "directory" => 21, "path" => "a" })
    assert_equal [true, JSON.generate(home)], invoke("resolve_directory", { "directory" => 21, "path" => nil })
  end

  def test_resolve_directory_rejects_what_it_cannot_resolve
    success, json = invoke("resolve_directory", { "directory" => 11 })
    refute success
    assert_includes JSON.parse(json), "resource"

    success, json = invoke("resolve_directory", { "directory" => 13 })
    refute success
    assert_includes JSON.parse(json), "config_dir"
  end

  def test_each_command_answers_through_the_store
    assert_equal [true, JSON.generate(Dir.pwd.tr("/", host_separator))], invoke("resolve", { "paths" => [] })
    assert_equal [true, JSON.generate("a#{host_separator}b")], invoke("normalize", { "path" => "a/./b" })
    assert_equal [true, JSON.generate("a#{host_separator}b")], invoke("join", { "paths" => ["a", "b"] })
    assert_equal [true, '"/a"'], invoke("dirname", { "path" => "/a/b" })
    assert_equal [true, '"json"'], invoke("extname", { "path" => "/a/b.json" })
    assert_equal [true, '"b"'], invoke("basename", { "path" => "/a/b.json", "ext" => ".json" })
    assert_equal [true, '"b.json"'], invoke("basename", { "path" => "/a/b.json" })
    assert_equal [true, JSON.generate(!windows_host?)], invoke("is_absolute", { "path" => "/a" })
  end

  def test_a_command_error_rejects_with_tauris_message
    assert_equal [false, '"path does not have a parent"'], invoke("dirname", { "path" => "/" })
    assert_equal [false, '"path does not have an extension"'], invoke("extname", { "path" => "a" })
    assert_equal [false, '"path does not have a basename"'], invoke("basename", { "path" => "/" })
  end

  # resolve starts at std::env::current_dir, and fails with
  # Error::CurrentDir when the directory is gone (plugin.rs:106).
  def test_resolve_rejects_when_the_current_directory_is_gone
    skip "Windows cannot remove a process's current directory" if Gem.win_platform?

    home = Dir.pwd
    gone = Dir.mktmpdir("tokra-gone")
    begin
      Dir.chdir(gone)
      Dir.rmdir(gone)

      answer = invoke("resolve", { "paths" => ["a"] })
    ensure
      Dir.chdir(home)
    end

    assert_equal [false, JSON.generate("failed to read current dir: No such file or directory (os error 2)")], answer
  end

  # Each argument reads as its Rust type does, and the first that does not
  # rejects with Tauri's invalid args message.
  def test_arguments_fail_in_serdes_words
    {
      ["resolve_directory", {}] => "command resolve_directory missing required key directory",
      ["resolve_directory", { "directory" => "x", "path" => 1 }] =>
        "invalid args `directory` for command `resolve_directory`: invalid type: string \"x\", expected u16",
      ["resolve_directory", { "directory" => 0 }] =>
        "invalid args `directory` for command `resolve_directory`: invalid value: 0, expected one of: " \
        "#{(1..23).to_a.join(', ')}",
      ["resolve_directory", { "directory" => 21, "path" => 1 }] =>
        "invalid args `path` for command `resolve_directory`: invalid type: integer `1`, expected path string",
      ["resolve", { "paths" => "a" }] =>
        "invalid args `paths` for command `resolve`: invalid type: string \"a\", expected a sequence",
      ["normalize", { "path" => 1 }] => "invalid args `path` for command `normalize`: invalid type: integer `1`, expected a string",
      ["join", { "paths" => [1] }] => "invalid args `paths` for command `join`: invalid type: integer `1`, expected a string",
      ["dirname", {}] => "invalid args `path` for command `dirname`: command dirname missing required key path",
      ["extname", { "path" => nil }] => "invalid args `path` for command `extname`: invalid type: null, expected a string",
      ["basename", { "path" => 1, "ext" => 1 }] =>
        "invalid args `path` for command `basename`: invalid type: integer `1`, expected a borrowed string",
      ["basename", { "path" => "a", "ext" => 1 }] =>
        "invalid args `ext` for command `basename`: invalid type: integer `1`, expected a borrowed string",
      ["is_absolute", { "path" => [] }] =>
        "invalid args `path` for command `is_absolute`: invalid type: sequence, expected a string",
    }.each do |(command, payload), message|
      expected = message.start_with?("invalid args") ? message : "invalid args `directory` for command `#{command}`: #{message}"
      assert_equal [false, JSON.generate(expected)], invoke(command, payload), "#{command} #{payload.inspect}"
    end
  end

  def test_another_command_is_not_the_plugins
    handled = @handle.manager.plugins.extend_api("path", request("nope", {}) { flunk "answered" })

    refute handled
  end

  private def invoke(command, payload)
    answer = nil
    handled = @handle.manager.plugins.extend_api("path", request(command, payload) { |success, json| answer = [success, json] })
    assert handled, command
    answer
  end

  private def request(command, payload, &responder)
    Tokra::Ipc::Invoke.new(command:, payload:, headers: {}, responder:, webview: @webview)
  end
end
