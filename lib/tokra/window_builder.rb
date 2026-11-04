# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WindowBuilder adapted from tauri/crates/tauri/src/window/mod.rs and
#                      tauri-runtime-wry/src/lib.rs WindowBuilderWrapper

module Tokra
  # The window rows of a WebviewWindowBuilder, as Tauri's WindowBuilder
  # holds them (window/mod.rs:120-133, 429-906). Each row records what
  # tauri-runtime-wry's WindowBuilderWrapper hands tao (lib.rs:813-1260),
  # and #native_attributes gives Native::Window#open all of it at once
  # (plan 052, decision c2).
  #
  # WindowBuilder#build, a window with no webview, arrives with child
  # webviews (plan 052, phase 4); until then a WebviewWindowBuilder holds
  # one, and this class is internal.
  class WindowBuilder # :nodoc:
    # The title a window has when you set none: Tauri's default,
    # "Tauri App", named for Tokra (tauri-runtime-wry lib.rs:813-835), the
    # same string a config window's title defaults to (config.rs:2061-2063;
    # plan 054, decision 7).
    DEFAULT_TITLE = "Tokra App"

    # The Windows window class a window has when you set none: Tauri's
    # "Tauri Window", named for Tokra as the title is (lib.rs:829-832).
    DEFAULT_WINDOW_CLASSNAME = "Tokra Window"

    # Tauri's WindowBuilder::new (window/mod.rs:207-218): tao's defaults,
    # then WindowBuilderWrapper::new's: focused, macOS's Visible title bar,
    # the title, and the Windows class (lib.rs:813-835). Keys for another
    # platform's rows are sent everywhere and read only there.
    def initialize(manager, label)
      raise TypeError, "wrong argument type #{label.class} (expected String)" unless label.is_a?(String)

      @manager = manager
      @label = label
      @menu = nil
      @menu_event_handler = nil
      @window_effects = nil
      @attributes = {
        title: DEFAULT_TITLE,
        inner_size: nil,
        position: nil,
        inner_size_constraints: [nil, nil, nil, nil],
        center: false,
        prevent_overflow: nil,
        resizable: true,
        maximizable: true,
        minimizable: true,
        closable: true,
        fullscreen: false,
        focused: true,
        focusable: true,
        maximized: false,
        visible: true,
        transparent: false,
        decorations: true,
        always_on_bottom: false,
        always_on_top: false,
        visible_on_all_workspaces: false,
        content_protected: false,
        icon: nil,
        skip_taskbar: false,
        window_classname: DEFAULT_WINDOW_CLASSNAME,
        shadow: nil,
        parent: nil,
        drag_and_drop: true,
        title_bar_style: TitleBarStyle::Visible.name,
        hidden_title: false,
        tabbing_identifier: nil,
        theme: nil,
        background_color: nil,
        cursor_moved_event: true,
      } #: Hash[Symbol, Native::Window::attribute]
      @constraints = [nil, nil, nil, nil] #: Array[(LogicalUnit | PhysicalUnit)?]
    end

    # Tauri's WindowBuilder::from_config (window/mod.rs:250-275): new's
    # defaults, then the rows tauri-runtime-wry's WindowBuilderWrapper
    # reads from +config+, a Utils::Config::WindowConfig (lib.rs:837-948),
    # the config's effects, and the window +parent+ names, which must
    # exist: Error::WindowNotFound otherwise.
    def self.from_config(manager, config)
      builder = new(manager, config.label)
      builder.__send__(:with_config, config)
      builder.__send__(:config_parent, manager, config.parent) if config.parent
      builder
    end

    # The label the window will have.
    attr_reader :label

    # The block #on_menu_event gave, or +nil+.
    attr_reader :menu_event_handler

    # The WindowEffectsConfig #effects gave, or +nil+.
    attr_reader :window_effects

    # The attributes Native::Window#open builds the window with: a fresh
    # Hash, its constraints in the native's <tt>[physical, value]</tt>
    # form.
    def native_attributes
      limits = @constraints.map do |limit|
        limit && [limit.is_a?(PhysicalUnit), Float(limit.value)] #: Native::Window::unit
      end
      @attributes.merge(inner_size_constraints: limits)
    end

    # The window's menu: the builder's, which is the window's own, or the
    # app's, kept in the menus stash either way (window/mod.rs:363-375,
    # manager/menu.rs:54-65).
    def window_menu(handle)
      menu = @menu || handle.menu
      return nil unless menu

      handle.menu_manager.insert_menu_into_stash(menu)
      Window::WindowMenu.new(is_app_wide: @menu.nil?, menu:)
    end

    # Tauri's WindowBuilder::menu (window/mod.rs:434-437).
    def menu(menu)
      expect(menu, Menu::Menu)
      @menu = menu
      self
    end

    # Tauri's WindowBuilder::on_menu_event (window/mod.rs:316-322).
    def on_menu_event(&handler)
      @menu_event_handler = handler
      self
    end

    # Tauri's WindowBuilder::center (window/mod.rs:441-444; lib.rs:950-953).
    def center
      set(:center, true)
    end

    # Tauri's WindowBuilder::position, logical (window/mod.rs:448-451;
    # lib.rs:955-958).
    def position(x, y)
      set(:position, [Float(x), Float(y)])
    end

    # Tauri's WindowBuilder::inner_size, logical (window/mod.rs:455-460;
    # lib.rs:960-965).
    def inner_size(width, height)
      set(:inner_size, [Float(width), Float(height)])
    end

    # Tauri's WindowBuilder::min_inner_size: tao sets the two minimums
    # (window/mod.rs:462-465; lib.rs:967-972; tao window.rs:348-354).
    def min_inner_size(min_width, min_height)
      @constraints[0] = LogicalUnit.new(Float(min_width))
      @constraints[1] = LogicalUnit.new(Float(min_height))
      self
    end

    # Tauri's WindowBuilder::max_inner_size: tao sets the two maximums
    # (window/mod.rs:469-472; lib.rs:974-979; tao window.rs:362-368).
    def max_inner_size(max_width, max_height)
      @constraints[2] = LogicalUnit.new(Float(max_width))
      @constraints[3] = LogicalUnit.new(Float(max_height))
      self
    end

    # Tauri's WindowBuilder::inner_size_constraints, which replaces all
    # four limits (window/mod.rs:476-482; lib.rs:981-989).
    def inner_size_constraints(constraints)
      expect(constraints, WindowSizeConstraints)
      @constraints = [constraints.min_width, constraints.min_height, constraints.max_width, constraints.max_height]
      self
    end

    # Tauri's WindowBuilder::prevent_overflow, a margin of physical zero
    # (window/mod.rs:493-496; lib.rs:996-1001).
    def prevent_overflow
      set(:prevent_overflow, [true, 0.0, 0.0])
    end

    # Tauri's WindowBuilder::prevent_overflow_with_margin
    # (window/mod.rs:507-512; lib.rs:1009-1012).
    def prevent_overflow_with_margin(margin)
      set(:prevent_overflow, size_dimensions(margin))
    end

    # Tauri's WindowBuilder::resizable (window/mod.rs:517-520).
    def resizable(resizable)
      flag(:resizable, resizable)
    end

    # Tauri's WindowBuilder::maximizable (window/mod.rs:530-533).
    def maximizable(maximizable)
      flag(:maximizable, maximizable)
    end

    # Tauri's WindowBuilder::minimizable (window/mod.rs:541-544).
    def minimizable(minimizable)
      flag(:minimizable, minimizable)
    end

    # Tauri's WindowBuilder::closable (window/mod.rs:554-557).
    def closable(closable)
      flag(:closable, closable)
    end

    # Tauri's WindowBuilder::title (window/mod.rs:561-564).
    def title(title)
      expect(title, String)
      set(:title, title.dup)
    end

    # Tauri's WindowBuilder::fullscreen, borderless on the current monitor
    # (window/mod.rs:568-571; lib.rs:1039-1048).
    def fullscreen(fullscreen)
      flag(:fullscreen, fullscreen)
    end

    # The note of Tauri's #[deprecated] on WindowBuilder::focus
    # (window/mod.rs:575-578).
    FOCUS_DEPRECATION = "The window is automatically focused by default. This function Will be removed in 3.0.0. " \
      "Use `focused` instead."

    # Tauri's deprecated WindowBuilder::focus (window/mod.rs:579-582),
    # warned under Ruby's :deprecated category (plan 052, decision c11).
    def focus
      WindowBuilder.warn_focus_deprecated(self.class)
      focused(true)
    end

    # Warns, under Ruby's :deprecated category, that +builder_class+'s
    # #focus is deprecated, with Tauri's note, naming the class the caller
    # used.
    def self.warn_focus_deprecated(builder_class)
      Warning.warn("#{builder_class}#focus is deprecated. #{FOCUS_DEPRECATION}\n", category: :deprecated)
    end

    # Tauri's WindowBuilder::focused (window/mod.rs:586-589).
    def focused(focused)
      flag(:focused, focused)
    end

    # Tauri's WindowBuilder::focusable (window/mod.rs:593-596).
    def focusable(focusable)
      flag(:focusable, focusable)
    end

    # Tauri's WindowBuilder::maximized (window/mod.rs:600-603).
    def maximized(maximized)
      flag(:maximized, maximized)
    end

    # Tauri's WindowBuilder::visible (window/mod.rs:607-610).
    def visible(visible)
      flag(:visible, visible)
    end

    # Tauri's WindowBuilder::theme, a Theme or +nil+ for the system's
    # (window/mod.rs:618-621; lib.rs:1227-1238).
    def theme(theme)
      expect(theme, Theme) if theme
      set(:theme, theme&.name)
    end

    # Tauri's WindowBuilder::decorations (window/mod.rs:638-641).
    def decorations(decorations)
      flag(:decorations, decorations)
    end

    # Tauri's WindowBuilder::always_on_bottom (window/mod.rs:645-648).
    def always_on_bottom(always_on_bottom)
      flag(:always_on_bottom, always_on_bottom)
    end

    # Tauri's WindowBuilder::always_on_top (window/mod.rs:652-655).
    def always_on_top(always_on_top)
      flag(:always_on_top, always_on_top)
    end

    # Tauri's WindowBuilder::visible_on_all_workspaces (window/mod.rs:663-668).
    def visible_on_all_workspaces(visible_on_all_workspaces)
      flag(:visible_on_all_workspaces, visible_on_all_workspaces)
    end

    # Tauri's WindowBuilder::content_protected (window/mod.rs:672-675).
    def content_protected(protected)
      flag(:content_protected, protected)
    end

    # Tauri's WindowBuilder::icon: the image becomes tao's icon here, so a
    # bad one raises at once, as Window#set_icon's does (window/mod.rs:678-681;
    # lib.rs:1197-1202).
    def icon(icon)
      expect(icon, Image)
      native = begin
        Native::Icon.from_rgba(icon.rgba, icon.width, icon.height)
      rescue RuntimeError => e
        raise Error::Runtime, "invalid icon: #{e.message}"
      end
      set(:icon, native)
    end

    # Tauri's WindowBuilder::skip_taskbar; macOS has no taskbar
    # (window/mod.rs:689-692; lib.rs:1209-1225).
    def skip_taskbar(skip)
      flag(:skip_taskbar, skip)
    end

    # Tauri's WindowBuilder::window_classname, read only on Windows
    # (window/mod.rs:696-699; lib.rs:1251-1259).
    def window_classname(classname)
      expect(classname, String)
      set(:window_classname, classname.dup)
    end

    # Tauri's WindowBuilder::shadow (window/mod.rs:711-714; lib.rs:1103-1113).
    def shadow(enable)
      flag(:shadow, enable)
    end

    # Tauri's WindowBuilder::parent, which asks the parent's handle at
    # once (window/mod.rs:727-758; plan 052, decision c6).
    def parent(parent)
      expect(parent, Window)
      set(:parent, open_native(parent))
    end

    # Tauri's WindowBuilder::effects, applied once the window exists
    # (window/mod.rs:889-892, 411-424).
    def effects(effects)
      expect(effects, WindowEffectsConfig)
      @window_effects = effects
      self
    end

    # Tauri's WindowBuilder::background_color (window/mod.rs:902-905;
    # lib.rs:1204-1207).
    def background_color(color)
      expect(color, Color)
      set(:background_color, [color.red, color.green, color.blue, color.alpha])
    end

    # WindowBuilderWrapper::with_config's rows, in its order
    # (tauri-runtime-wry lib.rs:837-948), and WindowBuilder::from_config's
    # effects (window/mod.rs:255).
    #
    # On macOS, with_config also hands tao the traffic-light inset, which
    # Tokra's window has no row for. tao would apply it in its view's
    # drawRect: (tao platform_impl/macos/view.rs:343-348), but wry puts its
    # own view in tao's place (wry wkwebview/mod.rs:636), so that inset
    # never runs; the webview's row, which WebviewBuilder.from_config sets,
    # is the one that moves the buttons (wkwebview/mod.rs:616-626).
    #
    # Where Tauri builds without macos-private-api, a debug build prints
    # that a transparent window needs it, naming the macOSPrivateApi key
    # (lib.rs:859-869). Tokra reads that key and does not act on it yet
    # (plan 052, question 2), so a message telling you to set it would
    # mislead, and it prints nothing. Until then a config window's
    # <tt>transparent</tt> is ignored on macOS without a word.
    private def with_config(config)
      if App.os_name == "macos"
        hidden_title(config.hidden_title).title_bar_style(config.title_bar_style)
        tabbing_identifier(config.tabbing_identifier) if config.tabbing_identifier
      else
        transparent(config.transparent)
      end
      # "Mouse event is disabled on Linux since sudden event bursts could
      # block event loop" (lib.rs:871-881). Only Linux reads the key, so it
      # is set everywhere, as every other platform's row is sent.
      set(:cursor_moved_event, false)
      title(config.title).inner_size(config.width, config.height).focused(config.focus).focusable(config.focusable)
        .visible(config.visible).resizable(config.resizable).fullscreen(config.fullscreen)
        .decorations(config.decorations).maximized(config.maximized).always_on_bottom(config.always_on_bottom)
        .always_on_top(config.always_on_top).visible_on_all_workspaces(config.visible_on_all_workspaces)
        .content_protected(config.content_protected).skip_taskbar(config.skip_taskbar).theme(config.theme)
        .closable(config.closable).maximizable(config.maximizable).minimizable(config.minimizable)
        .shadow(config.shadow)
      limits = [config.min_width, config.min_height, config.max_width, config.max_height]
      background_color(config.background_color) if config.background_color
      @constraints = limits.map { |limit| limit && LogicalUnit.new(limit) }
      x = config.x
      y = config.y
      position(x, y) if x && y
      center if config.center
      window_classname(config.window_classname) if config.window_classname
      config_prevent_overflow(config.prevent_overflow)
      @window_effects = config.window_effects
      nil
    end

    # with_config's <tt>preventOverflow</tt>: +true+ for a margin of zero,
    # a margin for a physical one, and nothing for +false+ (lib.rs:938-946).
    private def config_prevent_overflow(prevent_overflow)
      case prevent_overflow
      when Utils::Config::PreventOverflowConfig::Enable
        self.prevent_overflow if prevent_overflow.enabled
      when Utils::Config::PreventOverflowConfig::Margin
        margin = prevent_overflow.margin
        prevent_overflow_with_margin(PhysicalSize.new(width: margin.width, height: margin.height))
      end
      nil
    end

    # Makes the window +label+ names the parent, as from_config does, or
    # raises Error::WindowNotFound when none has it (window/mod.rs:266-272).
    private def config_parent(manager, label)
      window = manager.get_window(label)
      raise Error::WindowNotFound unless window

      parent(window)
      nil
    end

    # The native of +window+, which a main-thread getter finds open, as
    # Tauri's hwnd, gtk_window, and ns_window are window getters that fail
    # for a window its runtime no longer holds.
    private def open_native(window)
      native = window.native
      found = window.app_handle.runtime_context.getter { native.id }
      raise Error::Runtime, Error::Runtime::FAILED_TO_RECEIVE_MESSAGE if found.nil?

      native
    end

    # Records +value+ under +key+ and answers the builder.
    private def set(key, value)
      @attributes[key] = value
      self
    end

    # Records +value+ as a boolean, by Ruby's truthiness, as the native
    # setters read theirs (plan 052, decision c5).
    private def flag(key, value)
      set(key, value ? true : false)
    end

    # The native <tt>[physical, width, height]</tt> for a LogicalSize or a
    # PhysicalSize.
    private def size_dimensions(size)
      case size
      when LogicalSize then [false, Float(size.width), Float(size.height)]
      when PhysicalSize then [true, Float(size.width), Float(size.height)]
      else raise TypeError, "wrong argument type #{size.class} (expected Tokra::LogicalSize or Tokra::PhysicalSize)"
      end
    end

    # Raises TypeError, in Ruby's words, unless +value+ is a +type+.
    private def expect(value, type)
      raise TypeError, "wrong argument type #{value.class} (expected #{type})" unless value.is_a?(type)

      nil
    end
  end
end

# SPDX-SnippetEnd
