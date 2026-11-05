# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "fileutils"
require "tmpdir"
require_relative "support/stub_native"
require_relative "support/test_app"

# The config's app.trayIcon: codegen decodes its iconPath into the
# context (tauri-codegen context.rs:291-300; lib.rs:445-459), and App#run
# builds the tray from it after the app menu and before the setup hook,
# as Tauri's Builder::build does (app.rs:2265-2287; plan 049, part B;
# plan 054, phase 3). StubNative's tray records what tray-icon would be
# asked.
class TestConfigTray < Minitest::Test
  Codegen = Tokra::Codegen
  ICONS = File.expand_path("fixtures/config/icons", __dir__)
  TRAY = { "iconPath" => "icons/icon.png" }.freeze

  def setup
    StubNative.clear_event
    @dir = File.realpath(Dir.mktmpdir("tokra-tray"))
    icon("icons/icon.png", "rgba.png")
  end

  def teardown
    StubNative.clear_event
    FileUtils.rm_rf(@dir)
    Thread.current[:config_tray_seen] = nil
  end

  # --- the context: Context#tray_icon and codegen ---

  def test_a_context_has_no_tray_icon_until_one_is_set
    context = build_test_context
    assert_nil context.tray_icon

    image = Tokra::Image.new(rgba: "\x01\x02\x03\x04".b, width: 1, height: 1)
    assert_nil context.set_tray_icon(image)
    assert_same image, context.tray_icon
    context.set_tray_icon(nil)
    assert_nil context.tray_icon
  end

  def test_set_tray_icon_takes_only_an_image_or_nil
    error = assert_raises(TypeError) { build_test_context.set_tray_icon("icon.png") }
    assert_equal "wrong argument type String (expected Tokra::Image)", error.message
  end

  def test_codegen_decodes_the_tray_icon_path_beside_the_config
    icon("art/tray.png", "rgba16.png")
    context = codegen("iconPath" => "art/tray.png")

    expected = Codegen::CachedIcon.new(File.join(@dir, "art", "tray.png")).value
    assert_equal expected, context.tray_icon
  end

  def test_codegen_decodes_an_ico_tray_icon_by_its_first_entry
    icon("tray.ico", "bmp.ico")
    assert_equal Codegen::CachedIcon.new(File.join(ICONS, "bmp.ico")).value, codegen("iconPath" => "tray.ico").tray_icon
  end

  def test_an_absolute_tray_icon_path_stands_alone
    context = codegen("iconPath" => File.join(ICONS, "rgba_interlaced.png"))
    assert_equal [5, 5], [context.tray_icon.width, context.tray_icon.height]
  end

  def test_a_config_without_a_tray_icon_leaves_the_context_without_one
    assert_nil codegen(nil).tray_icon
  end

  # CachedIcon::new returns InvalidImageExtension, and context_codegen
  # returns it (context.rs:294).
  def test_a_tray_icon_neither_png_nor_ico_is_an_invalid_image_extension
    icon("tray.jpg", "icon.jpg")
    error = assert_raises(Codegen::EmbeddedAssetsError::InvalidImageExtension) { codegen("iconPath" => "tray.jpg") }
    assert_equal "invalid extension `jpg` used for image #{rust_join('tray.jpg')}, must be `ico` or `png`",
      error.message
  end

  def test_a_missing_tray_icon_fails_with_the_joined_path
    error = assert_raises(RuntimeError) { codegen("iconPath" => "icons/missing.png") }
    assert error.message.start_with?("failed to open icon #{rust_join('icons/missing.png')}: "), error.message
  end

  # --- the build: App#run ---

  def test_run_builds_the_configured_tray_with_tauris_defaults
    found = []
    build_test_app(config: tray_config).run do |handle, event|
      found << handle.tray_by_id("main")&.native if event.is_a?(Tokra::RunEvent::Ready)
    end

    native = sole_tray
    assert_equal "main", native.id
    assert native.built_on_main_thread?
    attributes = native.attributes
    assert_instance_of Tokra::Native::TrayIcon::Icon, attributes["icon"]
    assert_equal [nil, nil, nil, nil, false, true],
      attributes.values_at("menu", "tooltip", "title", "temp_dir_path", "icon_is_template", "menu_on_left_click")
    assert_equal [native], found
  end

  def test_the_config_sets_the_id_title_tooltip_and_template
    config = tray_config("id" => "status", "title" => "Title", "tooltip" => "Tip", "iconAsTemplate" => true)
    found = []
    build_test_app(config:).run do |handle, event|
      found.push(handle.tray_by_id("main"), handle.tray_by_id("status")&.native) if event.is_a?(Tokra::RunEvent::Ready)
    end

    native = sole_tray
    assert_equal "status", native.id
    assert_equal ["Title", "Tip", true], native.attributes.values_at("title", "tooltip", "icon_is_template")
    assert_equal [nil, native], found
  end

  # Both flags set tray-icon's one menu_on_left_click, the deprecated one
  # first, so showMenuOnLeftClick wins (tray/mod.rs:300-324; plan 049,
  # decision 10).
  def test_show_menu_on_left_click_always_wins
    [
      [{ "menuOnLeftClick" => false }, true],
      [{ "showMenuOnLeftClick" => false }, false],
      [{ "menuOnLeftClick" => true, "showMenuOnLeftClick" => false }, false],
      [{ "menuOnLeftClick" => false, "showMenuOnLeftClick" => true }, true],
    ].each do |flags, expected|
      StubNative.clear_event
      build_test_app(config: tray_config(flags)).run
      assert_equal expected, sole_tray.attributes["menu_on_left_click"], flags.inspect
    end
  end

  def test_the_tray_takes_the_contexts_icon
    context = build_test_context(config: tray_config)
    image = Tokra::Image.new(rgba: [1, 2, 3, 4].pack("C*") * 6, width: 3, height: 2)
    context.set_tray_icon(image)
    app = Tokra::Builder.default.build(context, native: StubNative)
    app.run

    assert_same image, app.handle.tray_manager.icon
    assert_instance_of Tokra::Native::TrayIcon::Icon, sole_tray.attributes["icon"]
  end

  def test_a_context_whose_tray_icon_was_set_to_nil_gives_a_tray_without_one
    context = build_test_context(config: tray_config)
    context.set_tray_icon(nil)
    Tokra::Builder.default.build(context, native: StubNative).run

    assert_nil sole_tray.attributes["icon"]
  end

  # TrayIconBuilder::icon drops an image tray-icon refuses
  # (tray/mod.rs:251-257).
  def test_an_icon_tray_icon_refuses_is_dropped_and_the_tray_still_built
    context = build_test_context(config: tray_config)
    context.set_tray_icon(Tokra::Image.new(rgba: "\x00".b * 3, width: 1, height: 1))
    Tokra::Builder.default.build(context, native: StubNative).run

    assert_nil sole_tray.attributes["icon"]
  end

  def test_a_config_without_a_tray_icon_builds_no_tray
    build_test_app.run
    assert_empty StubNative::TrayIcon.instances
  end

  # Tauri's order: the app menu, the tray, the plugins and the setup hook,
  # then setup's config windows (app.rs:2232-2289, 2370-2384).
  def test_the_tray_comes_after_the_app_menu_and_before_the_setup_hook
    menu = Ractor.shareable_proc do |handle|
      Thread.current[:config_tray_seen] = [[:menu, StubNative::TrayIcon.instances.size]]
      Tokra::Menu::Menu.new(handle)
    end
    setup = Ractor.shareable_proc do |app|
      Thread.current[:config_tray_seen] << [:setup, app.tray_by_id("main")&.id&.to_s]
    end
    build_test_app(Tokra::Builder.default.menu(&menu).setup(&setup), config: tray_config).run

    assert_equal [[:menu, 0], [:setup, "main"]], Thread.current[:config_tray_seen]
  end

  def test_the_tray_is_built_before_the_config_windows
    config = tray_config.merge("app" => tray_config["app"].merge("windows" => [{ "label" => "not ok" }]))
    assert_raises(Tokra::Error::Runtime) { build_test_app(config:).run }

    assert_equal 1, StubNative::TrayIcon.instances.size
  end

  # Builder::build returns the tray's error (app.rs:2286).
  def test_a_tray_that_fails_to_build_ends_run_before_the_setup_hook
    StubNative::TrayIcon.fail_next = "not on the main thread"
    setup = Ractor.shareable_proc { |_app| Thread.current[:config_tray_seen] = :setup }
    app = build_test_app(Tokra::Builder.default.setup(&setup), config: tray_config)

    error = assert_raises(Tokra::Error::Tray) { app.run }
    assert_equal "tray icon error: not on the main thread", error.message
    assert_nil Thread.current[:config_tray_seen]
    assert_empty StubNative.windows
  end

  # The tray has no listener of its own: its events reach the app's
  # listeners, plugins, and the run callback (plan 043, decision 4), and
  # it sits in the app's resources table, where the page's
  # TrayIcon.getById finds it.
  def test_the_configured_trays_events_reach_the_app_and_the_run_callback
    StubNative.inject_event(Tokra::Native::TrayIconEvent.new("Click", "main", [1.0, 2.0], [0, 0, 4, 4], "Left", "Up"))
    Thread.current[:config_tray_seen] = []
    listener = Ractor.shareable_proc { |_handle, event| Thread.current[:config_tray_seen] << [:app, event.id.to_s] }
    app = build_test_app(Tokra::Builder.default.on_tray_icon_event(&listener), config: tray_config)
    app.run do |handle, event|
      case event
      when Tokra::RunEvent::Ready then Thread.current[:config_tray_seen] << [:own, handle.tray_manager.event_listeners.keys]
      when Tokra::RunEvent::TrayIconEvent then Thread.current[:config_tray_seen] << [:run, event.event.id.to_s]
      end
    end

    assert_equal [[:own, []], [:app, "main"], [:run, "main"]], Thread.current[:config_tray_seen]
  end

  def test_the_page_finds_the_configured_tray_by_its_id
    rids = []
    app = build_test_app(config: tray_config)
    app.run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      rids << handle.tray_manager.tray_resource_by_id("main")
      rids << handle.resources_table.get(rids.first).id.to_s
    end
    refute_nil rids.first
    assert_equal "main", rids.last
  end

  # The one tray tray-icon was asked for.
  private def sole_tray
    trays = StubNative::TrayIcon.instances
    assert_equal 1, trays.size, "trays built"
    trays.first
  end

  private def tray_config(fields = {})
    { "app" => { "trayIcon" => TRAY.merge(fields) } }
  end

  # +relative+ joined to @dir as Rust's Path::join displays it: on Windows
  # the parent's backslashes and one more, with +relative+ left as written.
  private def rust_join(relative)
    "#{Tokra::Utils::Config::Parse.display(@dir)}#{File::ALT_SEPARATOR || '/'}#{relative}"
  end

  private def icon(relative, fixture)
    path = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(File.join(ICONS, fixture), path)
  end

  # The context codegen makes from a config in @dir with +tray+ as its
  # app.trayIcon.
  private def codegen(tray)
    raw = { "identifier" => "com.tokra.tray", "app" => { "trayIcon" => tray }.compact }
    config = Tokra::Utils::Config::Config.deserialize(raw, @dir)
    Codegen.context_codegen(Codegen::ContextData.new(dev: false, config:, config_parent: @dir))
  end
end
