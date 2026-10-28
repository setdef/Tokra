# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TrayIconBuilder adapted from tauri/crates/tauri/src/tray/mod.rs

module Tokra
  module Tray
    # Builds a TrayIcon.
    #
    # Each method sets one thing about the tray and returns the builder;
    # #build puts the tray in the system tray. Build it once the app runs,
    # such as in the setup hook: before App#run builds the event loop,
    # #build raises Error::Tray (plan 043, decision 3).
    #
    # On Linux the icon may not show until the tray has a menu; an empty
    # Menu::Menu is enough.
    #
    # Mirrors Tauri's TrayIconBuilder (tray/mod.rs:201-390).
    #
    # === Example
    #
    #   Tokra::Tray::TrayIconBuilder.with_id("main")
    #     .icon(Tokra::Image.from_path("icon.png"))
    #     .tooltip("Tokra")
    #     .menu(Tokra::Menu::MenuBuilder.new(app).quit.build)
    #     .on_tray_icon_event { |tray, event| puts event.class }
    #     .build(app)
    class TrayIconBuilder
      # A builder whose tray has the id +id+.
      #
      # Mirrors Tauri's TrayIconBuilder::with_id (tray/mod.rs:224-234),
      # which also takes a number from tray-icon's counter.
      def self.with_id(id)
        new.tap { |builder| builder.__send__(:id=, TrayIconId.from(id)) }
      end

      # A builder whose tray takes the next id tray-icon makes, a number
      # as text.
      #
      # Mirrors Tauri's TrayIconBuilder::new (tray/mod.rs:210-222).
      def initialize
        @id = TrayIconId.new(value: Native::TrayIcon.next_id)
        @menu = nil #: (Native::Menu | Native::Submenu)?
        @icon = nil #: Native::TrayIcon::Icon?
        @tooltip = nil #: String?
        @title = nil #: String?
        @temp_dir_path = nil #: String?
        @icon_as_template = false
        @menu_on_left_click = true
        @on_menu_event = nil #: (^(AppHandle, Menu::MenuEvent) -> void)?
        @on_tray_icon_event = nil #: (^(TrayIcon, TrayIconEvent::event) -> void)?
      end

      # The id the tray this builder makes will have.
      #
      # Mirrors Tauri's TrayIconBuilder::id (tray/mod.rs:345-349).
      attr_reader :id

      # Gives the tray +menu+, a Menu::Menu or Menu::Submenu. On Linux a
      # tray's menu cannot be removed or replaced later, though its items
      # can change.
      #
      # Mirrors Tauri's TrayIconBuilder::menu (tray/mod.rs:236-244).
      def menu(menu)
        @menu = Tray.native_menu(menu)
        self
      end

      # Gives the tray +icon+, a Tokra::Image. An image whose bytes do not
      # make its size is dropped, and the tray keeps any icon set before,
      # as Tauri drops it.
      #
      # Mirrors Tauri's TrayIconBuilder::icon (tray/mod.rs:246-258).
      def icon(icon)
        @icon = Tray.tray_icon(icon)
        self
      rescue Error::BadTrayIcon
        self
      end

      # Shows +tooltip+ when the pointer rests on the tray. Linux shows no
      # tooltip.
      #
      # Mirrors Tauri's TrayIconBuilder::tooltip (tray/mod.rs:260-268).
      def tooltip(tooltip)
        @tooltip = tooltip.to_str
        self
      end

      # Shows +title+ beside the icon. On Linux it shows only with an
      # icon; Windows shows no title.
      #
      # Mirrors Tauri's TrayIconBuilder::title (tray/mod.rs:270-283).
      def title(title)
        @title = title.to_str
        self
      end

      # Writes the icon into the directory +path+, a String or Pathname.
      # Linux only, where it otherwise goes into
      # <tt>$XDG_RUNTIME_DIR/tray-icon</tt> or <tt>$TEMP/tray-icon</tt>.
      #
      # Mirrors Tauri's TrayIconBuilder::temp_dir_path (tray/mod.rs:285-292).
      def temp_dir_path(path)
        @temp_dir_path = case path
        when String then path
        else path.to_path
        end
        self
      end

      # Makes the icon a template, which macOS tints to suit the menu bar.
      # macOS only.
      #
      # Mirrors Tauri's TrayIconBuilder::icon_as_template
      # (tray/mod.rs:294-298).
      def icon_as_template(is_template)
        @icon_as_template = is_template
        self
      end

      # Whether a left click opens the menu; true unless told otherwise.
      # Linux does not support it.
      #
      # Mirrors Tauri's deprecated TrayIconBuilder::menu_on_left_click
      # (tray/mod.rs:300-312); use #show_menu_on_left_click.
      def menu_on_left_click(enable)
        @menu_on_left_click = enable
        self
      end

      # Whether a left click opens the menu; true unless told otherwise.
      # Linux does not support it.
      #
      # Mirrors Tauri's TrayIconBuilder::show_menu_on_left_click
      # (tray/mod.rs:314-322).
      def show_menu_on_left_click(enable)
        @menu_on_left_click = enable
        self
      end

      # Calls the block with the AppHandle and each Menu::MenuEvent, a
      # click on any menu item, this tray's or not. A second block
      # replaces the first.
      #
      # Mirrors Tauri's TrayIconBuilder::on_menu_event (tray/mod.rs:324-334).
      def on_menu_event(&handler)
        @on_menu_event = handler
        self
      end

      # Calls the block with the tray and each of its TrayIconEvent
      # events. A second block replaces the first.
      #
      # Mirrors Tauri's TrayIconBuilder::on_tray_icon_event
      # (tray/mod.rs:336-343).
      def on_tray_icon_event(&handler)
        @on_tray_icon_event = handler
        self
      end

      # Builds the tray, puts it in the system tray, and returns it.
      # Raises Error::Tray when the platform refuses it, and
      # Error::FailedToReceiveMessage when the main thread never answers.
      #
      # Mirrors Tauri's TrayIconBuilder::build (tray/mod.rs:385-389).
      def build(manager)
        tray, _rid = build_inner(manager.app_handle)
        tray
      end

      # Builds the tray on the main thread and registers it, answering it
      # and its rid (tray/mod.rs:351-383).
      def build_inner(app_handle) # :nodoc:
        attributes = {
"menu" => @menu,
"icon" => @icon,
"tooltip" => @tooltip,
"title" => @title,
"temp_dir_path" => @temp_dir_path,
"icon_is_template" => @icon_as_template,
"menu_on_left_click" => @menu_on_left_click,
}
        id = @id
        menu = @menu
        native = Tray.run_main_thread(app_handle) do
          Tray.refuse_unbuildable_menu(app_handle, menu)
          Tray.natives(app_handle).tray_icon.new(id.value, attributes)
        end
        tray = TrayIcon.new(id:, native:, app_handle:)
        rid = tray.register(@on_menu_event, @on_tray_icon_event)
        [tray, rid]
      end

      private attr_writer :id
    end
  end
end

# SPDX-SnippetEnd
