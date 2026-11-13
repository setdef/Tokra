# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "support/test_app"

# Tokra::Path::PathResolver answers each directory as Tauri's does on
# each desktop platform (path/desktop.rs, path/mod.rs). The dirs crate's
# answers come from a stand-in that answers as dirs 6.0.0 does there
# (src/mac.rs, src/lin.rs, src/win.rs) for a user +u+, and every expected
# path below is written out as Tauri builds it from those.
class TestPathResolver < Minitest::Test
  B = Tokra::Path::BaseDirectory
  T = Tokra::Utils::Platform::Target

  # The dirs crate as a Ruby object: one method per function, answering
  # a String or nil, and no method for a function it does not bind.
  class Dirs
    def initialize(**answers)
      answers.each { |name, answer| define_singleton_method(name) { answer } }
    end
  end

  # dirs 6.0.0 on macOS, src/mac.rs: everything under $HOME, and no
  # executable, runtime, or template directory.
  MACOS = {
    home_dir: "/Users/u",
    audio_dir: "/Users/u/Music",
    cache_dir: "/Users/u/Library/Caches",
    config_dir: "/Users/u/Library/Application Support",
    data_dir: "/Users/u/Library/Application Support",
    data_local_dir: "/Users/u/Library/Application Support",
    desktop_dir: "/Users/u/Desktop",
    document_dir: "/Users/u/Documents",
    download_dir: "/Users/u/Downloads",
    executable_dir: nil,
    font_dir: "/Users/u/Library/Fonts",
    picture_dir: "/Users/u/Pictures",
    public_dir: "/Users/u/Public",
    runtime_dir: nil,
    template_dir: nil,
    video_dir: "/Users/u/Movies",
  }.freeze

  # dirs 6.0.0 on Linux, src/lin.rs, with no XDG variable set and a
  # user-dirs.dirs naming the usual folders.
  LINUX = {
    home_dir: "/home/u",
    audio_dir: "/home/u/Music",
    cache_dir: "/home/u/.cache",
    config_dir: "/home/u/.config",
    data_dir: "/home/u/.local/share",
    data_local_dir: "/home/u/.local/share",
    desktop_dir: "/home/u/Desktop",
    document_dir: "/home/u/Documents",
    download_dir: "/home/u/Downloads",
    executable_dir: "/home/u/.local/bin",
    font_dir: "/home/u/.local/share/fonts",
    picture_dir: "/home/u/Pictures",
    public_dir: "/home/u/Public",
    runtime_dir: "/run/user/1000",
    template_dir: "/home/u/Templates",
    video_dir: "/home/u/Videos",
  }.freeze

  # dirs 6.0.0 on Windows, src/win.rs: the known folders, and no
  # executable, font, or runtime directory.
  WINDOWS = {
    home_dir: "C:\\Users\\u",
    audio_dir: "C:\\Users\\u\\Music",
    cache_dir: "C:\\Users\\u\\AppData\\Local",
    config_dir: "C:\\Users\\u\\AppData\\Roaming",
    data_dir: "C:\\Users\\u\\AppData\\Roaming",
    data_local_dir: "C:\\Users\\u\\AppData\\Local",
    desktop_dir: "C:\\Users\\u\\Desktop",
    document_dir: "C:\\Users\\u\\Documents",
    download_dir: "C:\\Users\\u\\Downloads",
    executable_dir: nil,
    font_dir: nil,
    picture_dir: "C:\\Users\\u\\Pictures",
    public_dir: "C:\\Users\\Public",
    runtime_dir: nil,
    template_dir: "C:\\Users\\u\\AppData\\Roaming\\Microsoft\\Windows\\Templates",
    video_dir: "C:\\Users\\u\\Videos",
  }.freeze

  # The method of PathResolver each dirs function answers.
  PLAIN = {
    audio_dir: :audio_dir,
    cache_dir: :cache_dir,
    config_dir: :config_dir,
    data_dir: :data_dir,
    local_data_dir: :data_local_dir,
    desktop_dir: :desktop_dir,
    document_dir: :document_dir,
    download_dir: :download_dir,
    executable_dir: :executable_dir,
    font_dir: :font_dir,
    home_dir: :home_dir,
    picture_dir: :picture_dir,
    public_dir: :public_dir,
    runtime_dir: :runtime_dir,
    template_dir: :template_dir,
    video_dir: :video_dir,
  }.freeze

  def setup
    @app = build_test_app
  end

  def test_each_plain_directory_is_the_dirs_crates_answer
    [[T::MacOS, MACOS], [T::Linux, LINUX], [T::Windows, WINDOWS]].each do |target, answers|
      resolver = resolver(target, answers)
      PLAIN.each do |method, function|
        answer = answers.fetch(function)
        if answer
          assert_equal Pathname.new(answer), resolver.public_send(method), "#{target.name} #{method}"
        else
          error = assert_raises(Tokra::Error::UnknownPath, "#{target.name} #{method}") { resolver.public_send(method) }
          assert_equal "unknown path", error.message
        end
      end
    end
  end

  def test_the_app_directories_on_macos
    resolver = resolver(T::MacOS, MACOS)

    assert_equal "/Users/u/Library/Application Support/com.tokra.test", resolver.app_config_dir.to_s
    assert_equal "/Users/u/Library/Application Support/com.tokra.test", resolver.app_data_dir.to_s
    assert_equal "/Users/u/Library/Application Support/com.tokra.test", resolver.app_local_data_dir.to_s
    assert_equal "/Users/u/Library/Caches/com.tokra.test", resolver.app_cache_dir.to_s
    assert_equal "/Users/u/Library/Logs/com.tokra.test", resolver.app_log_dir.to_s
  end

  def test_the_app_directories_on_linux
    resolver = resolver(T::Linux, LINUX)

    assert_equal "/home/u/.config/com.tokra.test", resolver.app_config_dir.to_s
    assert_equal "/home/u/.local/share/com.tokra.test", resolver.app_data_dir.to_s
    assert_equal "/home/u/.local/share/com.tokra.test", resolver.app_local_data_dir.to_s
    assert_equal "/home/u/.cache/com.tokra.test", resolver.app_cache_dir.to_s
    assert_equal "/home/u/.local/share/com.tokra.test/logs", resolver.app_log_dir.to_s
  end

  def test_the_app_directories_on_windows
    resolver = resolver(T::Windows, WINDOWS)

    assert_equal "C:\\Users\\u\\AppData\\Roaming\\com.tokra.test", resolver.app_config_dir.to_s
    assert_equal "C:\\Users\\u\\AppData\\Roaming\\com.tokra.test", resolver.app_data_dir.to_s
    assert_equal "C:\\Users\\u\\AppData\\Local\\com.tokra.test", resolver.app_local_data_dir.to_s
    assert_equal "C:\\Users\\u\\AppData\\Local\\com.tokra.test", resolver.app_cache_dir.to_s
    assert_equal "C:\\Users\\u\\AppData\\Local\\com.tokra.test\\logs", resolver.app_log_dir.to_s
  end

  def test_an_app_directory_is_unknown_when_its_base_is
    resolver = resolver(T::Linux, LINUX.merge(config_dir: nil, home_dir: nil, data_local_dir: nil))

    assert_raises(Tokra::Error::UnknownPath) { resolver.app_config_dir }
    assert_raises(Tokra::Error::UnknownPath) { resolver.app_log_dir }
    assert_raises(Tokra::Error::UnknownPath) { resolver(T::MacOS, MACOS.merge(home_dir: nil)).app_log_dir }
  end

  # The resolver reads the identifier each time, as Tauri's reads
  # config().identifier (desktop.rs:233-289).
  def test_the_app_directories_are_named_for_the_configs_identifier
    app = build_test_app(config: { "identifier" => "com.example.from-config" })
    resolver = Tokra::Path::PathResolver.new(app.handle, dirs: Dirs.new(**MACOS), target: T::MacOS)

    assert_equal "/Users/u/Library/Caches/com.example.from-config", resolver.app_cache_dir.to_s
  end

  # Until Tokra binds the whole dirs crate (plan 063, decision 1), a
  # directory whose dirs function the collaborator lacks says so.
  def test_a_directory_the_collaborator_cannot_answer_is_not_implemented
    resolver = resolver(T::Linux, LINUX.slice(:home_dir, :data_local_dir))

    error = assert_raises(NotImplementedError) { resolver.app_config_dir }
    assert_includes error.message, "config_dir"
    assert_raises(NotImplementedError) { resolver.cache_dir }
    assert_equal "/home/u/.local/share/com.tokra.test", resolver.app_local_data_dir.to_s
  end

  # std::env::temp_dir: TMPDIR on Unix, even empty, else /tmp off Apple
  # (Rust sys/paths/unix.rs:442-449).
  def test_the_temp_dir_on_unix
    assert_equal "/var/t", resolver(T::Linux, LINUX, env: { "TMPDIR" => "/var/t" }).temp_dir.to_s
    assert_equal "", resolver(T::Linux, LINUX, env: { "TMPDIR" => "" }).temp_dir.to_s
    assert_equal "/tmp", resolver(T::Linux, LINUX, env: {}).temp_dir.to_s
    assert_equal "/var/t", resolver(T::MacOS, MACOS, env: { "TMPDIR" => "/var/t" }).temp_dir.to_s
  end

  # On Apple platforms Rust asks confstr(_CS_DARWIN_USER_TEMP_DIR), as
  # Ruby's Etc.systmpdir does (ruby ext/etc/etc.c:738-775).
  def test_the_temp_dir_on_macos_without_tmpdir
    skip "confstr answers only on macOS" unless RUBY_PLATFORM.include?("darwin")

    temp = resolver(T::MacOS, MACOS, env: {}).temp_dir.to_s

    assert_match(%r{\A/.*/T/\z}, temp)
  end

  # GetTempPath2W, as Rust's env.rs:720-735 documents it for a process
  # that is not SYSTEM: TMP, TEMP, USERPROFILE, then the Windows
  # directory, ending in a backslash.
  def test_the_temp_dir_on_windows
    env = { "TMP" => "C:\\T", "TEMP" => "C:\\E", "USERPROFILE" => "C:\\Users\\u", "SystemRoot" => "C:\\Windows" }

    assert_equal "C:\\T\\", resolver(T::Windows, WINDOWS, env:).temp_dir.to_s
    assert_equal "C:\\E\\", resolver(T::Windows, WINDOWS, env: env.except("TMP")).temp_dir.to_s
    assert_equal "C:\\Users\\u\\", resolver(T::Windows, WINDOWS, env: env.except("TMP", "TEMP")).temp_dir.to_s
    assert_equal "C:\\Windows\\", resolver(T::Windows, WINDOWS, env: { "SystemRoot" => "C:\\Windows" }).temp_dir.to_s
    assert_equal "C:\\T\\", resolver(T::Windows, WINDOWS, env: { "TMP" => "C:\\T\\" }).temp_dir.to_s
  end

  # resource_dir waits on where Tokra keeps an app's resources (plan 063,
  # decision 7).
  def test_the_resource_dir_is_not_implemented
    error = assert_raises(NotImplementedError) { resolver(T::MacOS, MACOS).resource_dir }
    assert_includes error.message, "resource"
  end

  def test_file_name_is_the_last_name
    resolver = resolver(T::Linux, LINUX)

    assert_equal "b.json", resolver.file_name("/a/b.json")
    assert_equal "b", resolver.file_name("a/b/")
    assert_nil resolver.file_name("a/..")
    assert_nil resolver.file_name("/")
    assert_equal "b", resolver(T::Windows, WINDOWS).file_name("C:\\a\\b")
  end

  # resolve pushes the path onto the base directory (mod.rs:263-265,
  # 343-359), so an absolute path stands alone, as in the rustdoc's
  # example of $HOME/.config/path/to/something.
  def test_resolve_joins_a_path_to_a_base_directory
    linux = resolver(T::Linux, LINUX)
    windows = resolver(T::Windows, WINDOWS)

    assert_equal "/home/u/.config/path/to/something", linux.resolve("path/to/something", B::Config).to_s
    assert_equal "/home/u/.local/share/com.tokra.test/a.db", linux.resolve(Pathname.new("a.db"), B::AppData).to_s
    assert_equal "/etc/hosts", linux.resolve("/etc/hosts", B::Home).to_s
    assert_equal "/home/u/", linux.resolve("", B::Home).to_s
    assert_equal "C:\\Users\\u\\AppData\\Roaming\\com.tokra.test\\a\\b",
      windows.resolve("a\\b", B::AppConfig).to_s
    assert_equal "C:\\Users\\u\\a/b", windows.resolve("a/b", B::Home).to_s
    assert_equal "D:\\x", windows.resolve("D:\\x", B::Home).to_s
  end

  def test_resolve_fails_as_its_directory_does
    assert_raises(Tokra::Error::UnknownPath) { resolver(T::MacOS, MACOS).resolve("x", B::Runtime) }
    assert_raises(NotImplementedError) { resolver(T::MacOS, MACOS).resolve("x", B::Resource) }
  end

  # The bundler's rule for a resource path (mod.rs:343-357): a root is
  # _root_, a parent _up_, and . and a Windows prefix vanish.
  def test_a_resource_path_maps_its_root_and_parents
    resources = Class.new(Tokra::Path::PathResolver) do
      define_method(:resource_dir) { Pathname.new((target == T::Windows) ? "C:\\R" : "/r") }
    end
    unix = resources.new(@app.handle, dirs: Dirs.new(**LINUX), target: T::Linux)
    windows = resources.new(@app.handle, dirs: Dirs.new(**WINDOWS), target: T::Windows)

    assert_equal "/r/_up_/a/b", unix.resolve("../a/./b", B::Resource).to_s
    assert_equal "/r/_root_/etc/x", unix.resolve("/etc/x", B::Resource).to_s
    assert_equal "C:\\R\\_root_\\x\\_up_\\y", windows.resolve("D:\\x\\..\\y", B::Resource).to_s
  end

  # parse resolves a leading variable and drops every later ".."
  # (mod.rs:280-303).
  def test_parse_resolves_a_leading_variable
    linux = resolver(T::Linux, LINUX)
    windows = resolver(T::Windows, WINDOWS)

    assert_equal "/home/u/.bashrc", linux.parse("$HOME/.bashrc").to_s
    assert_equal "/home/u/.local/share/com.tokra.test/x", linux.parse("$APPDATA/../x").to_s
    assert_equal "../a/b", linux.parse("../a/../b").to_s
    assert_equal "/x/$HOME", linux.parse("/x/$HOME").to_s
    assert_equal "$NOPE/x", linux.parse("$NOPE/x").to_s
    assert_equal "./a/b", linux.parse("./a/b").to_s
    assert_equal "", linux.parse("").to_s
    assert_equal "C:\\Users\\u\\x", windows.parse("$HOME\\x").to_s
    assert_equal "C:\\foo\\bar", windows.parse("C:\\foo\\..\\bar").to_s
    assert_raises(Tokra::Error::UnknownPath) { resolver(T::MacOS, MACOS).parse("$RUNTIME/x") }
  end

  # Tauri's app.path() is the resolver the path plugin manages
  # (lib.rs:771-774, path/plugin.rs:236-249), so every handle answers the
  # same one.
  def test_every_handle_answers_the_managed_resolver
    handle = @app.handle
    resolver = handle.path

    assert_kind_of Tokra::Path::PathResolver, resolver
    assert_same resolver, @app.path
    assert_same resolver, handle.state(Tokra::Path::PathResolver)
  end

  # The resolver an app manages asks Tokra::Native, the dirs crate's
  # functions Tokra's extension binds.
  def test_the_managed_resolver_answers_from_the_extension
    resolver = @app.handle.path

    assert_equal Pathname.new(Tokra::Native.home_dir), resolver.home_dir
    assert_equal Pathname.new(Tokra::Native.data_local_dir), resolver.local_data_dir
    assert_equal "com.tokra.test", resolver.app_local_data_dir.basename.to_s
  end

  # Tokra::Path::Resolver stays as the resolver's name for the log
  # plugin, which names it.
  def test_the_old_name_is_the_resolver
    assert_same Tokra::Path::PathResolver, Tokra::Path::Resolver
  end

  private def resolver(target, answers, env: {})
    Tokra::Path::PathResolver.new(@app.handle, dirs: Dirs.new(**answers), target:, env:)
  end
end

# The real extension on the host, as dirs answers there.
class TestPathResolverIntegration < Minitest::Test
  def test_real_native_home_dir_returns_string_on_macos
    skip "macOS-only integration test" unless RUBY_PLATFORM.include?("darwin")

    result = Tokra::Native.home_dir

    assert_kind_of String, result
    assert_includes result, "/Users/"
  end

  def test_real_native_home_dir_returns_string_on_linux
    skip "Linux-only integration test" unless RUBY_PLATFORM.include?("linux")

    result = Tokra::Native.home_dir

    assert_kind_of String, result
    assert_includes result, "/home/"
  end

  def test_real_native_data_local_dir_returns_string_on_macos
    skip "macOS-only integration test" unless RUBY_PLATFORM.include?("darwin")

    result = Tokra::Native.data_local_dir

    assert_kind_of String, result
    assert_includes result, "Library/Application Support"
  end

  def test_real_native_data_local_dir_returns_string_on_linux
    skip "Linux-only integration test" unless RUBY_PLATFORM.include?("linux")

    result = Tokra::Native.data_local_dir

    assert_kind_of String, result
    assert_includes result, ".local/share"
  end

  def test_real_native_data_local_dir_returns_string_on_windows
    skip "Windows-only integration test" unless RUBY_PLATFORM.include?("mingw")

    result = Tokra::Native.data_local_dir

    assert_kind_of String, result
    assert_includes result, "AppData"
  end

  def test_real_app_log_dir_on_macos
    skip "macOS-only integration test" unless RUBY_PLATFORM.include?("darwin")

    result = build_test_app.path.app_log_dir

    assert_equal File.join(Tokra::Native.home_dir, "Library/Logs/com.tokra.test"), result.to_s
  end

  def test_real_app_log_dir_on_linux
    skip "Linux-only integration test" unless RUBY_PLATFORM.include?("linux")

    result = build_test_app.path.app_log_dir

    assert_equal File.join(Tokra::Native.data_local_dir, "com.tokra.test/logs"), result.to_s
  end
end
