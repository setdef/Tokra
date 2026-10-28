# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: The menu plugin adapted from tauri/crates/tauri/src/menu/plugin.rs and
#                      tauri-macros/src/menu.rs (do_menu_item!); the argument messages are
#                      serde's as serde_json produces them

module Tokra
  module Menu
    # Core plugin answering the <tt>plugin:menu|*</tt> commands, so the
    # menu classes of <tt>@tauri-apps/api</tt> work without setup.
    #
    # The page holds menus and items by resource id, in the calling
    # webview's ResourceTable. An item the page made with an +action+
    # hears its clicks through a channel, which this plugin sends each
    # MenuEvent's id down, after the app's listeners heard it.
    #
    # Mirrors Tauri's menu plugin (menu/plugin.rs). Where Tauri panics on
    # what the page sends, this rejects with the panic's text (plan 042,
    # decision 8).
    class Plugin < Tokra::Plugin
      # The channels of the page's items, by item id (plugin.rs:885).
      class MenuChannels # :nodoc:
        def initialize
          @mutex = Thread::Mutex.new
          @channels = {} #: Hash[MenuId, Ipc::Channel]
        end

        # Sends the item +id+'s clicks to +channel+.
        def insert(id, channel)
          @mutex.synchronize { @channels[id] = channel }
          nil
        end

        # The channel for the item +id+, or +nil+.
        def get(id)
          @mutex.synchronize { @channels[id] }
        end
      end

      # A command the plugin answers with an error the page reads.
      class Rejection < StandardError # :nodoc:
      end

      # The text of Rust's <tt>unreachable!()</tt> panic.
      UNREACHABLE = "internal error: entered unreachable code"

      # The text of Rust's panic for <tt>None.unwrap()</tt>.
      UNWRAP_NONE = "called `Option::unwrap()` on a `None` value"

      # Tauri's ItemKind (plugin.rs:22-30).
      ITEM_KINDS = %w[Menu MenuItem Predefined Submenu Check Icon].freeze

      # The variants of dpi's Position, the +at+ of +popup+ (dpi 0.1.2
      # src/lib.rs:741-746).
      POSITION_VARIANTS = %w[Physical Logical].freeze

      # Tauri's Predefined variants (plugin.rs:74-94), with the
      # PredefinedMenuItem constructor each calls.
      PREDEFINED = {
        "Separator" => :separator,
        "Copy" => :copy,
        "Cut" => :cut,
        "Paste" => :paste,
        "SelectAll" => :select_all,
        "Undo" => :undo,
        "Redo" => :redo,
        "Minimize" => :minimize,
        "Maximize" => :maximize,
        "Fullscreen" => :fullscreen,
        "Hide" => :hide,
        "HideOthers" => :hide_others,
        "ShowAll" => :show_all,
        "CloseWindow" => :close_window,
        "Quit" => :quit,
        "About" => :about,
        "Services" => :services,
      }.freeze

      # Tauri's NativeIcon variants (menu/mod.rs:361-474), which an icon
      # payload names.
      NATIVE_ICONS = %w[
        Add
        Advanced
        Bluetooth
        Bookmarks
        Caution
        ColorPanel
        ColumnView
        Computer
        EnterFullScreen
        Everyone
        ExitFullScreen
        FlowView
        Folder
        FolderBurnable
        FolderSmart
        FollowLinkFreestanding
        FontPanel
        GoLeft
        GoRight
        Home
        IChatTheater
        IconView
        Info
        InvalidDataFreestanding
        LeftFacingTriangle
        ListView
        LockLocked
        LockUnlocked
        MenuMixedState
        MenuOnState
        MobileMe
        MultipleDocuments
        Network
        Path
        PreferencesGeneral
        QuickLook
        RefreshFreestanding
        Refresh
        Remove
        RevealFreestanding
        RightFacingTriangle
        Share
        Slideshow
        SmartBadge
        StatusAvailable
        StatusNone
        StatusPartiallyAvailable
        StatusUnavailable
        StopProgressFreestanding
        StopProgress
        TrashEmpty
        TrashFull
        User
        UserAccounts
        UserGroup
        UserGuest
      ].freeze

      # The ItemKind each item class answers as (plugin.rs:574-586).
      KIND_NAMES = {
        MenuItem => "MenuItem",
        Submenu => "Submenu",
        PredefinedMenuItem => "Predefined",
        CheckMenuItem => "Check",
        IconMenuItem => "Icon",
      }.freeze

      # Every item kind, the kinds <tt>do_menu_item!</tt> takes by default
      # (tauri-macros menu.rs:88-94).
      ALL_ITEMS = %w[MenuItem Submenu Predefined Check Icon].freeze

      # The fields of the page's AboutMetadata, in order (plugin.rs:32-46).
      ABOUT_FIELDS = %w[
        name
        version
        shortVersion
        authors
        comments
        copyright
        license
        website
        websiteLabel
        credits
        icon
].freeze

      # A page's existing item: <tt>[rid, kind]</tt>.
      ExistingItem = Data.define(:rid, :kind) # :nodoc:
      # A Predefined item to make (plugin.rs:270-274).
      PredefinedPayload = Data.define(:item, :about, :text) # :nodoc:
      # A CheckMenuItem to make (plugin.rs:135-143).
      CheckPayload = Data.define(:handler, :id, :text, :checked, :enabled, :accelerator) # :nodoc:
      # An IconMenuItem to make (plugin.rs:182-191).
      IconPayload = Data.define(:handler, :id, :text, :icon, :enabled, :accelerator) # :nodoc:
      # A Submenu to make (plugin.rs:96-103).
      SubmenuPayload = Data.define(:id, :text, :enabled, :items, :icon) # :nodoc:
      # A MenuItem to make (plugin.rs:231-238).
      MenuItemPayload = Data.define(:handler, :id, :text, :enabled, :accelerator) # :nodoc:
      # The options of +new+ (plugin.rs:342-354).
      NewOptions = Data.define(:id, :text, :enabled, :checked, :accelerator, :item, :about, :icon, :items) # :nodoc:

      # Returns the plugin identifier.
      def name
        "menu"
      end

      # Manages the item channels, as Tauri's setup does (plugin.rs:887-892).
      def initialize(app, config = {})
        super
        app.manage(MenuChannels.new)
      end

      # Sends a clicked item's id to its channel, if the page gave it one
      # (plugin.rs:893-899).
      def on_event(app, event)
        return nil unless event.is_a?(RunEvent::MenuEvent)

        id = event.event.id
        channels = app.state(MenuChannels) #: MenuChannels
        channels.get(id)&.send(id.value) # rubocop:disable Style/Send
        nil
      rescue Tokra::Error
        nil
      end

      # Answers a <tt>plugin:menu|</tt> command. Returns +true+ when the
      # command is one of the plugin's, +false+ otherwise.
      def extend_api(invoke)
        answer = case invoke.command
        when "new" then new_item(invoke)
        when "append" then add_items(invoke, :append)
        when "prepend" then add_items(invoke, :prepend)
        when "insert" then insert_items(invoke)
        when "remove" then remove_item(invoke)
        when "remove_at" then remove_at(invoke)
        when "items" then list_items(invoke)
        when "get" then get_item(invoke)
        when "popup" then popup(invoke)
        when "create_default" then create_default(invoke)
        when "set_as_app_menu" then set_as_app_menu(invoke)
        when "set_as_window_menu" then set_as_window_menu(invoke)
        when "text" then with_menu_item(invoke, ALL_ITEMS, &:text)
        when "set_text" then set_text(invoke)
        when "is_enabled" then with_menu_item(invoke, ALL_ITEMS - ["Predefined"]) { |item| enableable(item).is_enabled }
        when "set_enabled" then set_enabled(invoke)
        when "set_accelerator" then set_accelerator(invoke)
        when "set_as_windows_menu_for_nsapp", "set_as_help_menu_for_nsapp" then set_nsapp_menu(invoke)
        when "is_checked" then check_item(invoke).is_checked
        when "set_checked" then set_checked(invoke)
        when "set_icon" then set_icon(invoke)
        else return false
        end
        invoke.resolve(answer)
        true
      rescue Tokra::Error, Rejection, Ipc::InvokeError, IndexError, ArgumentError => e
        invoke.reject(e.message)
        true
      end

      # +new+ (plugin.rs:356-463).
      private def new_item(invoke)
        kind = argument(invoke, "kind").deserialize { |value| item_kind(value) }
        options = argument(invoke, "options").deserialize_option { |value| new_options(value) } ||
          NewOptions.new(id: nil, text: nil, enabled: nil, checked: nil, accelerator: nil, item: nil, about: nil,
            icon: nil, items: nil)
        handler = Ipc::Channel.from_command(invoke, "handler")
        webview = invoke.webview
        table = webview.resources_table
        item = case kind
        when "Menu"
          builder = MenuBuilder.new(webview)
          builder.id(options.id) if options.id
          options.items&.each { |payload| with_item(webview, table, payload) { |made| builder.item(made) } }
          builder.build
        when "Submenu"
          create_submenu(webview, table, SubmenuPayload.new(id: options.id, text: options.text || "",
            enabled: options.enabled, items: options.items || [], icon: options.icon))
        when "MenuItem"
          create_menu_item(webview, MenuItemPayload.new(handler: nil, id: options.id, text: options.text || "",
            enabled: options.enabled, accelerator: options.accelerator))
        when "Predefined"
          raise Rejection, UNWRAP_NONE unless options.item

          create_predefined(webview, table, PredefinedPayload.new(item: options.item, about: options.about,
            text: options.text))
        when "Check"
          create_check(webview, CheckPayload.new(handler: nil, id: options.id, text: options.text || "",
            checked: options.checked || false, enabled: options.enabled, accelerator: options.accelerator))
        else
          create_icon(webview, table, IconPayload.new(handler: nil, id: options.id, text: options.text || "",
            icon: options.icon || NativeIcon::User, enabled: options.enabled, accelerator: options.accelerator))
        end
        rid = table.add(item)
        channels.insert(item.id, handler)
        [rid, item.id.value]
      end

      # +append+ and +prepend+ (plugin.rs:465-517).
      private def add_items(invoke, operation)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        payloads = argument(invoke, "items").deserialize { |value| payload_kinds(value) }
        webview = invoke.webview
        table = webview.resources_table
        menu = menu_or_submenu(table, rid, kind)
        payloads.each { |payload| with_item(webview, table, payload) { |item| menu.public_send(operation, item) } }
        nil
      end

      # +insert+ (plugin.rs:519-547).
      private def insert_items(invoke)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        payloads = argument(invoke, "items").deserialize { |value| payload_kinds(value) }
        position = argument(invoke, "position").deserialize { |value| usize(value) }
        webview = invoke.webview
        table = webview.resources_table
        menu = menu_or_submenu(table, rid, kind)
        payloads.each_with_index do |payload, index|
          with_item(webview, table, payload) { |item| menu.insert(item, position + index) }
        end
        nil
      end

      # +remove+ (plugin.rs:549-572).
      private def remove_item(invoke)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        item_rid, item_kind = argument(invoke, "item").deserialize { |value| existing_item(value) }
        table = invoke.webview.resources_table
        menu = menu_or_submenu(table, rid, kind)
        menu.remove(menu_item(table, item_rid, item_kind, ALL_ITEMS))
        nil
      end

      # +remove_at+ (plugin.rs:588-613).
      private def remove_at(invoke)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        position = argument(invoke, "position").deserialize { |value| usize(value) }
        table = invoke.webview.resources_table
        item = menu_or_submenu(table, rid, kind).remove_at(position)
        item && item_resource(table, item)
      end

      # +items+ (plugin.rs:615-634).
      private def list_items(invoke)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        table = invoke.webview.resources_table
        menu_or_submenu(table, rid, kind).items.map { |item| item_resource(table, item) }
      end

      # +get+ (plugin.rs:636-661).
      private def get_item(invoke)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        id = argument(invoke, "id").deserialize { |value| menu_id(value) }
        table = invoke.webview.resources_table
        item = menu_or_submenu(table, rid, kind).get(id)
        item && item_resource(table, item)
      end

      # +popup+ (plugin.rs:663-692): the named window, or the caller's, and
      # nothing when no window has that label. It answers once the menu
      # closes.
      private def popup(invoke)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        label = argument(invoke, "window").deserialize_option { |value| string(value) }
        at = argument(invoke, "at").deserialize_option { |value| position(value) }
        webview = invoke.webview
        window = label ? webview.app_handle.get_window(label) : webview.window
        return nil unless window

        menu = menu_or_submenu(webview.resources_table, rid, kind)
        at ? menu.popup_at(window, at) : menu.popup(window)
      end

      # +create_default+ (plugin.rs:694-704).
      private def create_default(invoke)
        menu = Menu.default(invoke.webview.app_handle)
        [invoke.webview.resources_table.add(menu), menu.id.value]
      end

      # +set_as_app_menu+ (plugin.rs:706-719).
      private def set_as_app_menu(invoke)
        rid = rid_arg(invoke)
        table = invoke.webview.resources_table
        previous = menu_resource(table, rid).set_as_app_menu
        previous && [table.add(previous), previous.id.value]
      end

      # +set_as_window_menu+ (plugin.rs:721-742): the named window, or the
      # caller's, and +nil+ when no window has that label.
      private def set_as_window_menu(invoke)
        rid = rid_arg(invoke)
        label = argument(invoke, "window").deserialize_option { |value| string(value) }
        webview = invoke.webview
        window = label ? webview.app_handle.get_window(label) : webview.window
        return nil unless window

        table = webview.resources_table
        previous = menu_resource(table, rid).set_as_window_menu(window)
        previous && [table.add(previous), previous.id.value]
      end

      # +set_text+ (plugin.rs:750-759).
      private def set_text(invoke)
        text = nil #: String?
        read = -> { text = argument(invoke, "text").deserialize { |value| string(value) } }
        with_menu_item(invoke, ALL_ITEMS, after: read) { |item| item.set_text(text.to_s) }
      end

      # +set_enabled+ (plugin.rs:771-786).
      private def set_enabled(invoke)
        enabled = nil #: bool?
        read = -> { enabled = argument(invoke, "enabled").deserialize { |value| boolean(value) } }
        with_menu_item(invoke, ALL_ITEMS - ["Predefined"], after: read) { |item| enableable(item).set_enabled(enabled == true) }
      end

      # +set_accelerator+ (plugin.rs:788-803).
      private def set_accelerator(invoke)
        accelerator = nil #: String?
        read = -> { accelerator = argument(invoke, "accelerator").deserialize_option { |value| string(value) } }
        with_menu_item(invoke, %w[MenuItem Check Icon], after: read) do |item|
          with_accelerator = item #: MenuItem | CheckMenuItem | IconMenuItem
          with_accelerator.set_accelerator(accelerator)
        end
      end

      # +set_as_windows_menu_for_nsapp+ and +set_as_help_menu_for_nsapp+
      # (plugin.rs:805-838). Both make the submenu NSApp's Help menu on
      # macOS, as Tauri's both call set_as_help_menu_for_nsapp; elsewhere
      # they do nothing.
      private def set_nsapp_menu(invoke)
        rid = rid_arg(invoke)
        return nil unless Tokra::Menu.natives(invoke.webview).nsapp?

        submenu_resource(invoke.webview.resources_table, rid).set_as_help_menu_for_nsapp
        nil
      end

      # +set_icon+ (plugin.rs:858-882): a native icon, an image, or with
      # +null+ neither, on an icon item or a submenu.
      private def set_icon(invoke)
        icon = nil #: NativeIcon | JsImage | nil
        read = -> { icon = argument(invoke, "icon").deserialize_option { |value| icon(value) } }
        table = invoke.webview.resources_table
        with_menu_item(invoke, %w[Icon Submenu], after: read) do |item|
          icon_item = item #: IconMenuItem | Submenu
          case icon
          when NativeIcon then icon_item.set_native_icon(icon)
          when JsImage then icon_item.set_icon(icon.into_img(table))
          else
            icon_item.set_icon(nil)
            icon_item.set_native_icon(nil)
          end
          nil
        end
      end

      # +set_checked+ (plugin.rs:847-856).
      private def set_checked(invoke)
        item = check_item(invoke)
        checked = argument(invoke, "checked").deserialize { |value| boolean(value) }
        item.set_checked(checked)
        nil
      end

      # The CheckMenuItem the +rid+ argument names (plugin.rs:840-845).
      private def check_item(invoke)
        rid = rid_arg(invoke)
        resource = invoke.webview.resources_table.get(rid)
        resource.is_a?(CheckMenuItem) ? resource : raise(Error::BadResourceId, rid)
      end

      # Runs the block with the item the +rid+ and +kind+ arguments name,
      # one of +kinds+, as <tt>do_menu_item!</tt> does; +after+ reads the
      # command's other arguments, which Tauri reads before it runs.
      private def with_menu_item(invoke, kinds, after: nil)
        rid = rid_arg(invoke)
        kind = kind_arg(invoke)
        after&.call
        yield menu_item(invoke.webview.resources_table, rid, kind, kinds)
      end

      # The Menu or Submenu +rid+ names, or the rejection Tauri gives any
      # other kind.
      private def menu_or_submenu(table, rid, kind)
        case kind
        when "Menu" then menu_resource(table, rid)
        when "Submenu" then submenu_resource(table, rid)
        else raise Rejection, "unexpected menu item kind"
        end
      end

      # The item +rid+ names, as <tt>do_menu_item!</tt> takes it: the kind
      # must be one of +kinds+, or Tauri reaches <tt>unreachable!()</tt>.
      private def menu_item(table, rid, kind, kinds)
        raise Rejection, UNREACHABLE unless kinds.include?(kind)

        resource = table.get(rid)
        item = case kind
        when "MenuItem" then resource if resource.is_a?(MenuItem)
        when "Submenu" then resource if resource.is_a?(Submenu)
        when "Predefined" then resource if resource.is_a?(PredefinedMenuItem)
        when "Check" then resource if resource.is_a?(CheckMenuItem)
        when "Icon" then resource if resource.is_a?(IconMenuItem)
        end
        item || raise(Error::BadResourceId, rid)
      end

      # +item+, which <tt>do_menu_item!</tt>'s kinds made one that can be
      # enabled.
      private def enableable(item)
        item #: MenuItem | Submenu | CheckMenuItem | IconMenuItem
      end

      # The Menu +rid+ names: Tauri's ResourceTable::get, which downcasts or
      # fails.
      private def menu_resource(table, rid)
        resource = table.get(rid)
        resource.is_a?(Menu) ? resource : raise(Error::BadResourceId, rid)
      end

      # The Submenu +rid+ names.
      private def submenu_resource(table, rid)
        resource = table.get(rid)
        resource.is_a?(Submenu) ? resource : raise(Error::BadResourceId, rid)
      end

      # The <tt>(rid, id, kind)</tt> Tauri answers for an item it adds to
      # the table (make_item_resource!, plugin.rs:574-586).
      private def item_resource(table, item)
        [table.add(item), item.id.value, KIND_NAMES.fetch(item.class)]
      end

      # Makes the item +payload+ describes, or finds the page's existing
      # one, and yields it (MenuItemPayloadKind::with_item, plugin.rs:322-340).
      private def with_item(webview, table, payload)
        item = case payload
        when ExistingItem then menu_item(table, payload.rid, payload.kind, ALL_ITEMS)
        when SubmenuPayload then create_submenu(webview, table, payload)
        when PredefinedPayload then create_predefined(webview, table, payload)
        when CheckPayload then create_check(webview, payload)
        when IconPayload then create_icon(webview, table, payload)
        else create_menu_item(webview, payload)
        end
        yield item
      end

      # SubmenuPayload::create_item (plugin.rs:105-133).
      private def create_submenu(webview, table, payload)
        builder = payload.id ? SubmenuBuilder.with_id(webview, payload.id, payload.text) : SubmenuBuilder.new(webview, payload.text)
        builder.enabled(payload.enabled) unless payload.enabled.nil?
        case (icon = payload.icon)
        when NativeIcon then builder.submenu_native_icon(icon)
        when JsImage then builder.submenu_icon(icon.into_img(table))
        end
        payload.items.each { |item| with_item(webview, table, item) { |made| builder.item(made) } }
        builder.build
      end

      # CheckMenuItemPayload::create_item (plugin.rs:145-173).
      private def create_check(webview, payload)
        builder = payload.id ? CheckMenuItemBuilder.with_id(payload.id, payload.text) : CheckMenuItemBuilder.new(payload.text)
        builder.accelerator(payload.accelerator) if payload.accelerator
        builder.enabled(payload.enabled) unless payload.enabled.nil?
        item = builder.checked(payload.checked).build(webview)
        listen(webview, item, payload.handler)
      end

      # IconMenuItemPayload::create_item (plugin.rs:193-229).
      private def create_icon(webview, table, payload)
        builder = payload.id ? IconMenuItemBuilder.with_id(payload.id, payload.text) : IconMenuItemBuilder.new(payload.text)
        builder.accelerator(payload.accelerator) if payload.accelerator
        builder.enabled(payload.enabled) unless payload.enabled.nil?
        icon = payload.icon
        icon.is_a?(NativeIcon) ? builder.native_icon(icon) : builder.icon(icon.into_img(table))
        listen(webview, builder.build(webview), payload.handler)
      end

      # MenuItemPayload::create_item (plugin.rs:240-268).
      private def create_menu_item(webview, payload)
        builder = payload.id ? MenuItemBuilder.with_id(payload.id, payload.text) : MenuItemBuilder.new(payload.text)
        builder.accelerator(payload.accelerator) if payload.accelerator
        builder.enabled(payload.enabled) unless payload.enabled.nil?
        listen(webview, builder.build(webview), payload.handler)
      end

      # PredefinedMenuItemPayload::create_item (plugin.rs:276-308).
      private def create_predefined(webview, table, payload)
        constructor = PREDEFINED.fetch(payload.item)
        case constructor
        when :separator then PredefinedMenuItem.separator(webview)
        when :about
          PredefinedMenuItem.about(webview, payload.text, payload.about && about_metadata_for(table, payload.about))
        else PredefinedMenuItem.public_send(constructor, webview, payload.text)
        end
      end

      # The AboutMetadata of the page's fields, its icon read from the
      # table (AboutMetadata::into_metadata, plugin.rs:48-72).
      private def about_metadata_for(table, fields)
        icon = fields[:icon] #: JsImage?
        AboutMetadata.new(**fields, icon: icon&.into_img(table))
      end

      # Sends +item+'s clicks to the page's channel +handler+, if any.
      private def listen(webview, item, handler)
        channels.insert(item.id, handler.channel_on(webview)) if handler
        item
      end

      private def channels
        @app.state(MenuChannels) #: MenuChannels
      end

      # --- Reading the page's payloads, in serde's words ---

      private def argument(invoke, key)
        Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
      end

      private def rid_arg(invoke)
        argument(invoke, "rid").u32
      end

      private def kind_arg(invoke)
        argument(invoke, "kind").deserialize { |value| item_kind(value) }
      end

      private def mismatch(message)
        Ipc::CommandItem::Mismatch.new(message)
      end

      private def string(value)
        value.is_a?(String) ? value : raise(Ipc::CommandItem::Mismatch.invalid_type(value, "a string"))
      end

      private def boolean(value)
        case value
        when true, false then value
        else raise Ipc::CommandItem::Mismatch.invalid_type(value, "a boolean")
        end
      end

      private def usize(value)
        unless value.is_a?(Integer) && Ipc::Unexpected::JSON_INTEGERS.cover?(value)
          raise Ipc::CommandItem::Mismatch.invalid_type(value, "usize")
        end
        raise mismatch("invalid value: integer `#{value}`, expected usize") if value.negative?

        value
      end

      private def menu_id(value)
        MenuId.new(value: string(value))
      end

      # A unit-variant enum such as ItemKind, as serde_json reads it: a
      # string, or a map of the one variant to +null+.
      private def unit_enum(value, variants)
        variant, content = enum_variant(value, variants)
        raise Ipc::CommandItem::Mismatch.invalid_type(content, "unit") unless content.nil?

        variant
      end

      # The variant and content of an externally tagged enum, as
      # serde_json's deserialize_enum takes it; +content+ is +nil+ for a
      # bare string.
      private def enum_variant(value, variants)
        case value
        when String then [known_variant(value, variants), nil]
        when Hash
          raise mismatch("invalid value: map, expected map with a single key") unless value.size == 1

          name, content = value.first #: [String, json_value]
          [known_variant(name, variants), content]
        else raise Ipc::CommandItem::Mismatch.invalid_type(value, "string or map")
        end
      end

      # The variant +name+, or serde's unknown_variant error, which lists
      # the variants as serde's OneOf does (serde_core 1.0.228
      # de/mod.rs:2333-2356).
      private def known_variant(name, variants)
        return name if variants.include?(name)

        names = variants.map { |v| "`#{v}`" }
        expected = case names.size
        when 1 then names.first
        when 2 then names.join(" or ")
        else "one of #{names.join(', ')}"
        end
        raise mismatch("unknown variant `#{name}`, expected #{expected}")
      end

      # dpi's Position, an externally tagged enum of two newtype variants:
      # a PhysicalPosition of +i32+ or a LogicalPosition of +f64+, as
      # serde's derive and serde_json read it (dpi 0.1.2
      # src/lib.rs:387-391, 463-467, 741-746; serde_json 1.0.145
      # src/value/de.rs:1073-1083).
      private def position(value)
        if value.is_a?(String)
          known_variant(value, POSITION_VARIANTS)
          raise mismatch("invalid type: unit variant, expected newtype variant")
        end

        variant, content = enum_variant(value, POSITION_VARIANTS)
        if variant == "Physical"
          x, y = position_fields(content, "PhysicalPosition") { |field| Ipc::CommandItem.integer(field, "i32") }
          PhysicalPosition.new(x:, y:)
        else
          x, y = position_fields(content, "LogicalPosition") { |field| f64(field) }
          LogicalPosition.new(x:, y:)
        end
      end

      # A position's +x+ and +y+, each read by the block, as serde's derive
      # reads a struct: from a map, its fields' errors in key order, then
      # the first missing field; from a sequence, element by element, then
      # serde_json's error for elements left over (src/value/de.rs:195-211).
      private def position_fields(value, name, &read)
        case value
        when Hash
          present = %w[x y].select { |key| value.key?(key) }
          fields = present.map { |key| read.call(value[key]) }
          missing = (%w[x y] - present).first
          raise mismatch("missing field `#{missing}`") if missing

          [fields.fetch(0), fields.fetch(1)]
        when Array
          fields = Array.new(2) do |index|
            raise mismatch("invalid length #{index}, expected struct #{name} with 2 elements") if index >= value.size

            read.call(value[index])
          end
          raise mismatch("invalid length #{value.size}, expected fewer elements in array") if value.size > 2

          [fields.fetch(0), fields.fetch(1)]
        else raise Ipc::CommandItem::Mismatch.invalid_type(value, "struct #{name}")
        end
      end

      # A JSON number as Rust's +f64+: serde_json gives an integer or a
      # float to an f64 visitor, and rejects anything else.
      private def f64(value)
        case value
        when Integer, Float then Float(value)
        else raise Ipc::CommandItem::Mismatch.invalid_type(value, "f64")
        end
      end

      private def item_kind(value)
        unit_enum(value, ITEM_KINDS)
      end

      # A Predefined variant, and the About item's metadata Hash or +nil+.
      private def predefined(value)
        if value.is_a?(String) && value == "About"
          raise mismatch("invalid type: unit variant, expected newtype variant")
        end

        variant, content = enum_variant(value, PREDEFINED.keys)
        if variant == "About"
          [variant, content.nil? ? nil : about_fields(content)]
        else
          raise Ipc::CommandItem::Mismatch.invalid_type(content, "unit") unless content.nil?

          [variant, nil]
        end
      end

      # The fields of a struct, from a map or, as serde's derive also
      # takes, a sequence of exactly its fields in order.
      private def struct_fields(value, name, fields)
        case value
        when Hash then value
        when Array
          unless value.size == fields.size
            raise mismatch("invalid length #{value.size}, expected struct #{name} with #{fields.size} elements")
          end

          fields.zip(value).to_h
        else raise Ipc::CommandItem::Mismatch.invalid_type(value, "struct #{name}")
        end
      end

      private def required(hash, key)
        raise mismatch("missing field `#{key}`") unless hash.key?(key)

        yield hash[key]
      end

      private def optional(hash, key)
        value = hash[key]
        value.nil? ? nil : yield(value)
      end

      # AboutMetadata (plugin.rs:32-46), as keyword arguments.
      private def about_fields(value)
        hash = struct_fields(value, "AboutMetadata", ABOUT_FIELDS)
        text = -> (key) { optional(hash, key) { |v| string(v) } }
        {
          name: text.call("name"),
          version: text.call("version"),
          short_version: text.call("shortVersion"),
          authors: optional(hash, "authors") { |v| strings(v) },
          comments: text.call("comments"),
          copyright: text.call("copyright"),
          license: text.call("license"),
          website: text.call("website"),
          website_label: text.call("websiteLabel"),
          credits: text.call("credits"),
          icon: optional(hash, "icon") { |v| JsImage.deserialize(v) },
        }
      end

      private def strings(value)
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a sequence") unless value.is_a?(Array)

        value.map { |item| string(item) }
      end

      private def channel_id(value)
        text = string(value)
        Ipc::JavaScriptChannelId.from_str(text)
      rescue ArgumentError
        raise mismatch("invalid channel value `#{text}`, expected a string in the `#{Ipc::Channel::IPC_PAYLOAD_PREFIX}ID` format")
      end

      # The Icon untagged enum (plugin.rs:175-180): a NativeIcon, by its
      # name, or a JsImage.
      private def icon(value)
        return NativeIcon.const_get(value, false) if value.is_a?(String) && NATIVE_ICONS.include?(value)

        JsImage.deserialize(value)
      rescue Ipc::CommandItem::Mismatch
        raise mismatch("data did not match any variant of untagged enum Icon")
      end

      # NewOptions (plugin.rs:342-354).
      private def new_options(value)
        hash = struct_fields(value, "NewOptions", %w[id text enabled checked accelerator item icon items])
        item, about = optional(hash, "item") { |v| predefined(v) }
        NewOptions.new(
          id: optional(hash, "id") { |v| menu_id(v) },
          text: optional(hash, "text") { |v| string(v) },
          enabled: optional(hash, "enabled") { |v| boolean(v) },
          checked: optional(hash, "checked") { |v| boolean(v) },
          accelerator: optional(hash, "accelerator") { |v| string(v) },
          item:, about:,
          icon: optional(hash, "icon") { |v| icon(v) },
          items: optional(hash, "items") { |v| payload_kinds(v) }
        )
      end

      # A sequence of MenuItemPayloadKind.
      private def payload_kinds(value)
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a sequence") unless value.is_a?(Array)

        value.map { |item| payload_kind(item) }
      end

      # The <tt>(ResourceId, ItemKind)</tt> tuple.
      private def existing_item(value)
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a tuple of size 2") unless value.is_a?(Array)
        raise mismatch("invalid length #{value.size}, expected a tuple of size 2") if value.size < 2
        raise mismatch("invalid length #{value.size}, expected fewer elements in array") if value.size > 2

        [Ipc::CommandItem.integer(value[0], "u32"), item_kind(value[1])]
      end

      # MenuItemPayloadKind, the untagged enum (plugin.rs:310-320): the
      # first variant that reads wins.
      private def payload_kind(value)
        %i[existing_payload predefined_payload check_payload icon_payload submenu_payload menu_item_payload].each do |variant|
          return __send__(variant, value)
        rescue Ipc::CommandItem::Mismatch
          next
        end
        raise mismatch("data did not match any variant of untagged enum MenuItemPayloadKind")
      end

      private def existing_payload(value)
        rid, kind = existing_item(value)
        ExistingItem.new(rid:, kind:)
      end

      private def predefined_payload(value)
        hash = struct_fields(value, "PredefinedMenuItemPayload", %w[item text])
        item, about = required(hash, "item") { |v| predefined(v) }
        PredefinedPayload.new(item:, about:, text: optional(hash, "text") { |v| string(v) })
      end

      private def check_payload(value)
        hash = struct_fields(value, "CheckMenuItemPayload", %w[handler id text checked enabled accelerator])
        CheckPayload.new(
          handler: optional(hash, "handler") { |v| channel_id(v) },
          id: optional(hash, "id") { |v| menu_id(v) },
          text: required(hash, "text") { |v| string(v) },
          checked: required(hash, "checked") { |v| boolean(v) },
          enabled: optional(hash, "enabled") { |v| boolean(v) },
          accelerator: optional(hash, "accelerator") { |v| string(v) }
        )
      end

      private def icon_payload(value)
        hash = struct_fields(value, "IconMenuItemPayload", %w[handler id text icon enabled accelerator])
        IconPayload.new(
          handler: optional(hash, "handler") { |v| channel_id(v) },
          id: optional(hash, "id") { |v| menu_id(v) },
          text: required(hash, "text") { |v| string(v) },
          icon: required(hash, "icon") { |v| icon(v) },
          enabled: optional(hash, "enabled") { |v| boolean(v) },
          accelerator: optional(hash, "accelerator") { |v| string(v) }
        )
      end

      private def submenu_payload(value)
        hash = struct_fields(value, "SubmenuPayload", %w[id text enabled items icon])
        SubmenuPayload.new(
          id: optional(hash, "id") { |v| menu_id(v) },
          text: required(hash, "text") { |v| string(v) },
          enabled: optional(hash, "enabled") { |v| boolean(v) },
          items: required(hash, "items") { |v| payload_kinds(v) },
          icon: optional(hash, "icon") { |v| icon(v) }
        )
      end

      private def menu_item_payload(value)
        hash = struct_fields(value, "MenuItemPayload", %w[handler id text enabled accelerator])
        MenuItemPayload.new(
          handler: optional(hash, "handler") { |v| channel_id(v) },
          id: optional(hash, "id") { |v| menu_id(v) },
          text: required(hash, "text") { |v| string(v) },
          enabled: optional(hash, "enabled") { |v| boolean(v) },
          accelerator: optional(hash, "accelerator") { |v| string(v) }
        )
      end
    end
  end
end

# SPDX-SnippetEnd
