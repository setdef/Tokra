# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "fileutils"
require "tmpdir"

# The icons codegen puts in the context (tauri-codegen context.rs:213-268,
# find_icon at :493-507): which file each target reads, and what the
# context, the app, and its windows do with it (lib.rs:433-443;
# manager/window.rs:66-77; app.rs:871-874, 2413-2429; plan 054, phase 3).
class TestCodegenIcons < Minitest::Test
  Codegen = Tokra::Codegen
  Target = Tokra::Utils::Platform::Target
  ICONS = File.expand_path("fixtures/config/icons", __dir__)
  APP_ICON = File.join(TestApp::CONFIG_PARENT, "icons", "icon.png")

  def setup
    @dir = File.realpath(Dir.mktmpdir("tokra-icons"))
    StubNative.app_icons.clear
  end

  def teardown
    FileUtils.rm_rf(@dir)
    StubNative.app_icons.clear
  end

  # --- which file: find_icon over bundle.icon ---

  def test_unix_targets_read_icons_icon_png_beside_the_config
    icon("icons/icon.png", "rgba.png")
    [Target::MacOS, Target::Linux].each do |target|
      assert_equal [3, 2], size(Codegen.default_window_icon(config, @dir, target)), target.name
    end
  end

  def test_the_first_png_bundle_icon_lists_comes_first
    icon("icons/icon.png", "rgba.png")
    icon("art/first.png", "rgba_interlaced.png")
    icon("art/second.png", "rgba16.png")
    listed = config("icons/32x32.ico", "art/first.png", "art/second.png")
    assert_equal [5, 5], size(Codegen.default_window_icon(listed, @dir, Target::Linux))
  end

  def test_an_absolute_bundle_icon_stands_alone
    listed = config(File.join(ICONS, "rgba.png"))
    assert_equal [3, 2], size(Codegen.default_window_icon(listed, "/nowhere", Target::MacOS))
  end

  # A backslash is no separator on Unix, so Path::join joins the entry as
  # a relative name, and the file is one named with a backslash.
  def test_a_bundle_icon_starting_with_a_backslash_joins_on_unix
    skip "a backslash is a separator on Windows" if File::ALT_SEPARATOR

    icon("\\art.png", "rgba_interlaced.png")
    assert_equal [5, 5], size(Codegen.default_window_icon(config("\\art.png"), @dir, Target::Linux))
  end

  # On Windows, Path::join keeps the parent's drive for an entry with a
  # root but no prefix, and lets an entry with a drive stand alone.
  def test_a_rooted_bundle_icon_keeps_the_parents_drive_on_windows
    skip "only Windows paths have drives" unless File::ALT_SEPARATOR

    drive = @dir[/\A[A-Za-z]:/]
    joined = { "\\nowhere\\a.png" => "#{drive}\\nowhere\\a.png", "/nowhere/a.png" => "#{drive}/nowhere/a.png" }
    joined.merge("Q:nowhere.png" => "Q:nowhere.png").each do |entry, expected|
      error = assert_raises(RuntimeError, entry) { Codegen.default_window_icon(config(entry), @dir, Target::Linux) }
      assert error.message.start_with?("failed to open icon #{expected}: "), error.message
    end
  end

  def test_windows_reads_icons_icon_ico_first
    icon("icons/icon.png", "rgba16.png")
    icon("icons/icon.ico", "bmp.ico")
    assert_equal [2, 3], size(Codegen.default_window_icon(config, @dir, Target::Windows))
  end

  def test_windows_reads_the_first_ico_bundle_icon_lists
    icon("icons/icon.ico", "bmp.ico")
    icon("art/app.ico", "icon.ico")
    listed = config("art/app.png", "art/app.ico")
    assert_equal [3, 2], size(Codegen.default_window_icon(listed, @dir, Target::Windows))
  end

  def test_windows_falls_back_to_the_png_when_no_ico_exists
    icon("icons/icon.png", "rgba.png")
    assert_equal [3, 2], size(Codegen.default_window_icon(config("art/missing.ico"), @dir, Target::Windows))
  end

  # Codegen indexes entries()[0], which panics on an empty directory
  # (image.rs:57; plan 054, decision 8).
  def test_an_ico_without_entries_raises_rusts_index_message
    icon("icons/icon.ico", "empty.ico")
    error = assert_raises(RuntimeError) { Codegen.default_window_icon(config, @dir, Target::Windows) }
    assert_equal "index out of bounds: the len is 0 but the index is 0", error.message
  end

  # The predicate is String#ends_with, so a name that only holds ".png"
  # is passed over for the default.
  def test_a_bundle_icon_not_ending_in_png_is_passed_over
    icon("icons/icon.png", "rgba.png")
    listed = config("icons/icon.png.jpg", "icons/icon.PNG")
    assert_equal [3, 2], size(Codegen.default_window_icon(listed, @dir, Target::Linux))
  end

  # --- the app icon: macOS in development, raw ---

  def test_the_app_icon_is_the_first_icns_raw_on_macos_in_development
    icon("icons/icon.png", "rgba.png")
    icon("icons/icon.icns", "icon.icns")
    listed = config("icons/icon.icns")
    assert_equal File.binread(File.join(ICONS, "icon.icns")), Codegen.app_icon(listed, @dir, Target::MacOS, true)
  end

  def test_the_app_icon_falls_back_to_the_first_png_raw
    icon("icons/icon.png", "rgba.png")
    assert_equal File.binread(File.join(ICONS, "rgba.png")), Codegen.app_icon(config, @dir, Target::MacOS, true)
  end

  def test_there_is_no_app_icon_outside_macos_development
    icon("icons/icon.png", "rgba.png")
    assert_nil Codegen.app_icon(config, @dir, Target::MacOS, false)
    assert_nil Codegen.app_icon(config, @dir, Target::Linux, true)
    assert_nil Codegen.app_icon(config, @dir, Target::Windows, true)
  end

  # --- generate_context ---

  # As a Tauri app without icons/icon.png fails to compile, a Tokra app
  # without one fails to start, naming the path as Rust displays it.
  def test_generate_context_without_the_icon_fails_to_open_it
    File.write(File.join(@dir, "tokra.conf.json"), '{"identifier": "com.tokra.icons"}')
    error = assert_raises(RuntimeError) { Tokra.generate_context(File.join(@dir, "tokra.conf.json")) }
    expected = "#{Tokra::Utils::Config::Parse.display(@dir)}#{File::ALT_SEPARATOR || '/'}icons/icon.png"
    std = assert_raises(RuntimeError) { Tokra::Native.fs_read(expected) }.message
    # The icons folder itself is missing: POSIX says ENOENT (2) either way,
    # while Windows says ERROR_PATH_NOT_FOUND (3) when a folder on the way
    # is missing, rather than ERROR_FILE_NOT_FOUND (2).
    assert_match(/\(os error #{Gem.win_platform? ? 3 : 2}\)\z/, std)
    assert_equal "failed to open icon #{expected}: #{std}", error.message
  end

  def test_generate_context_holds_the_icons
    File.write(File.join(@dir, "tokra.conf.json"), '{"identifier": "com.tokra.icons"}')
    icon("icons/icon.png", "rgba.png")
    context = Tokra.generate_context(File.join(@dir, "tokra.conf.json"))
    assert_equal Codegen::CachedIcon.new(File.join(ICONS, "rgba.png")).value, context.default_window_icon
    if Target.current == Target::MacOS
      assert_equal File.binread(File.join(ICONS, "rgba.png")), context.app_icon
    else
      assert_nil context.app_icon
    end
  end

  # --- Context ---

  def test_set_default_window_icon_replaces_or_clears_it
    context = build_test_context
    image = Tokra::Image.new(rgba: "\xFF".b * 4, width: 1, height: 1)
    assert_nil context.set_default_window_icon(image)
    assert_same image, context.default_window_icon
    context.set_default_window_icon(nil)
    assert_nil context.default_window_icon
    error = assert_raises(TypeError) { context.set_default_window_icon("icon.png") }
    assert_equal "wrong argument type String (expected Tokra::Image)", error.message
  end

  def test_new_checks_the_app_icon
    context = build_test_context
    error = assert_raises(TypeError) do
      Tokra::Context.new(config: context.config, default_window_icon: nil, app_icon: 1,
        package_info: context.package_info, pattern: context.pattern)
    end
    assert_equal "wrong argument type Integer (expected String)", error.message
  end

  # --- windows: manager/window.rs:66-77 ---

  def test_a_window_without_an_icon_takes_the_default
    context = build_test_context
    app = Tokra::Builder.default.build(context, native: StubNative)
    assert_same context.default_window_icon, app.default_window_icon
    assert_same context.default_window_icon, app.handle.default_window_icon
    default = context.default_window_icon
    from_rgba = Tokra::Native::Icon.method(:from_rgba)
    made = {}
    main = Tokra::Native::Icon.stub(:from_rgba, -> (*args) { from_rgba.call(*args).tap { |icon| made[icon] = args } }) do
      run_and_find_window(app)
    end
    # tao's icon for the window is the one made from the default's pixels.
    assert_equal [default.rgba, default.width, default.height], made.fetch(main.attributes[:icon])
  end

  # A default tao refuses would fail every window that takes it, so a
  # window that builds proves it kept its own (has_icon).
  def test_a_window_with_its_own_icon_keeps_it
    context = build_test_context(config: { "app" => { "windows" => [] } })
    context.set_default_window_icon(Codegen::CachedIcon.new(File.join(ICONS, "rgba16.png")).value)
    own = Tokra::Image.new(rgba: "\x00".b * 16, width: 2, height: 2)
    built = nil
    run_test_context(context) do |handle|
      built = Tokra::WebviewWindowBuilder.new(handle, "own", page).icon(own).build.window.native
    end
    assert_kind_of Tokra::Native::Icon, built.attributes[:icon]
  end

  def test_a_context_without_a_default_gives_windows_none
    context = build_test_context
    context.set_default_window_icon(nil)
    app = Tokra::Builder.default.build(context, native: StubNative)
    assert_nil app.default_window_icon
    assert_nil run_and_find_window(app).attributes[:icon]
  end

  # A 16-bit PNG decodes to eight bytes a pixel, which tao refuses as an
  # icon of that size; Tauri's prepare_window returns the error.
  def test_a_default_tao_refuses_fails_the_window
    context = build_test_context(config: { "app" => { "windows" => [] } })
    context.set_default_window_icon(Codegen::CachedIcon.new(File.join(ICONS, "rgba16.png")).value)
    error = nil
    run_test_context(context) do |handle|
      error = assert_raises(Tokra::Error::Runtime) { Tokra::WebviewWindowBuilder.new(handle, "side", page).build }
    end
    assert_match(/\Aruntime error: invalid icon: The specified dimensions \(2x2\)/, error.message)
  end

  # --- the macOS app icon at Ready: app.rs:2413-2429 ---

  def test_the_app_icon_reaches_nsapp_before_ready_in_development
    skip "NSApp's icon is macOS's" unless Tokra::Native.respond_to?(:set_app_icon_for_nsapp)

    context = build_test_context
    seen = nil
    Tokra::Builder.default.build(context, native: StubNative).run do |_handle, event|
      seen = StubNative.app_icons.dup if event.is_a?(Tokra::RunEvent::Ready)
    end
    assert_equal [File.binread(APP_ICON)], seen
  end

  def test_no_app_icon_reaches_nsapp_when_packaged
    skip "NSApp's icon is macOS's" unless Tokra::Native.respond_to?(:set_app_icon_for_nsapp)

    context = build_test_context
    context.dev = false
    Tokra::Builder.default.build(context, native: StubNative).run { |_handle, _event| nil }
    assert_empty StubNative.app_icons
  end

  private def icon(relative, fixture)
    path = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(File.join(ICONS, fixture), path)
  end

  private def config(*bundle_icons)
    Tokra::Utils::Config::Config.deserialize({ "identifier" => "com.tokra.icons", "bundle" => { "icon" => bundle_icons } },
      @dir)
  end

  private def size(image)
    [image.width, image.height]
  end

  private def page
    Tokra::WebviewUrl::App.new("index.html")
  end

  private def run_and_find_window(app)
    app.run { |_handle, _event| nil }
    StubNative.windows.reverse.find { |window| window.label == "main" }
  end

  private def run_test_context(context, &on_ready)
    Tokra::Builder.default.build(context, native: StubNative).run do |handle, event|
      on_ready.call(handle) if event.is_a?(Tokra::RunEvent::Ready)
    end
  end
end
