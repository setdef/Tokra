# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: The tray plugin adapted from tauri/crates/tauri/src/tray/plugin.rs; the
#                      argument messages are serde's as serde_json produces them

module Tokra
  module Tray
    # Core plugin answering the <tt>plugin:tray|*</tt> commands, so the
    # TrayIcon class of <tt>@tauri-apps/api</tt> works without setup.
    #
    # The page holds trays by resource id in the app's ResourceTable, and
    # their menus and images by resource id in its own webview's. A tray
    # the page made hears its events through the channel it passed, which
    # receives each TrayIconEvent as its JSON.
    #
    # Mirrors Tauri's tray plugin (tray/plugin.rs).
    class Plugin < Tokra::Plugin
      # A command the plugin answers with an error the page reads.
      class Rejection < StandardError # :nodoc:
      end

      # The fields of TrayIconOptions, camelCase, in order (plugin.rs:23-35).
      OPTION_FIELDS = %w[
        id
        menu
        icon
        tooltip
        title
        tempDirPath
        iconAsTemplate
        menuOnLeftClick
        showMenuOnLeftClick
].freeze

      # The page's TrayIconOptions (plugin.rs:23-35).
      Options = Data.define(:id, :menu, :icon, :tooltip, :title, :temp_dir_path, :icon_as_template, # :nodoc:
        :menu_on_left_click, :show_menu_on_left_click)

      # Returns the plugin identifier.
      def name
        "tray"
      end

      # Answers a <tt>plugin:tray|</tt> command. Returns +true+ when the
      # command is one of the plugin's, +false+ otherwise.
      def extend_api(invoke)
        answer = case invoke.command
        when "new" then new_tray(invoke)
        when "get_by_id" then @app.tray_manager.tray_resource_by_id(id_arg(invoke))
        when "remove_by_id" then remove_by_id(invoke)
        when "set_icon" then set_icon(invoke)
        when "set_menu" then set_menu(invoke)
        when "set_tooltip" then with_text(invoke, "tooltip") { |tray, text| tray.set_tooltip(text) }
        when "set_title" then with_text(invoke, "title") { |tray, text| tray.set_title(text) }
        when "set_visible" then with_flag(invoke, "visible") { |tray, flag| tray.set_visible(flag) }
        when "set_temp_dir_path" then set_temp_dir_path(invoke)
        when "set_icon_as_template" then with_flag(invoke, "asTemplate") { |tray, flag| tray.set_icon_as_template(flag) }
        when "set_show_menu_on_left_click"
          with_flag(invoke, "onLeft") { |tray, flag| tray.set_show_menu_on_left_click(flag) }
        else return false
        end
        invoke.resolve(answer)
        true
      rescue Tokra::Error, Rejection, Ipc::InvokeError, ArgumentError => e
        invoke.reject(e.message)
        true
      end

      # +new+ (plugin.rs:37-95).
      private def new_tray(invoke)
        options = argument(invoke, "options").deserialize { |value| options(value) }
        handler = Ipc::Channel.from_command(invoke, "handler")
        builder = options.id ? TrayIconBuilder.with_id(options.id) : TrayIconBuilder.new
        builder.on_tray_icon_event { |_tray, event| send_event(handler, event) }
        table = invoke.webview.resources_table
        if (menu = options.menu)
          menu_rid, kind = menu
          builder.menu(menu_or_submenu(table, menu_rid, kind))
        end
        builder.icon(options.icon.into_img(table)) if options.icon
        builder.tooltip(options.tooltip) if options.tooltip
        builder.title(options.title) if options.title
        builder.temp_dir_path(options.temp_dir_path) if options.temp_dir_path
        builder.icon_as_template(options.icon_as_template) unless options.icon_as_template.nil?
        builder.menu_on_left_click(options.menu_on_left_click) unless options.menu_on_left_click.nil?
        builder.show_menu_on_left_click(options.show_menu_on_left_click) unless options.show_menu_on_left_click.nil?
        tray, rid = builder.build_inner(invoke.webview.app_handle)
        [rid, tray.id.value]
      end

      # Sends +event+ to the page's channel, ignoring a failed send, as
      # Tauri's <tt>let _ = handler.send(e)</tt> does (plugin.rs:49-51).
      private def send_event(handler, event)
        handler.send(event.as_json) # rubocop:disable Style/Send
      rescue Tokra::Error
        nil
      end

      # +remove_by_id+ (plugin.rs:102-108).
      private def remove_by_id(invoke)
        id = id_arg(invoke)
        return nil if @app.remove_tray_by_id(id)

        raise Rejection, "Can't find a tray associated with this id: #{id}"
      end

      # +set_icon+ (plugin.rs:110-125): the tray from the app's table, the
      # image from the webview's.
      private def set_icon(invoke)
        rid = rid_arg(invoke)
        icon = argument(invoke, "icon").deserialize_option { |value| JsImage.deserialize(value) }
        tray = tray(rid)
        tray.set_icon(icon&.into_img(invoke.webview.resources_table))
      end

      # +set_menu+ (plugin.rs:127-153).
      private def set_menu(invoke)
        rid = rid_arg(invoke)
        menu = argument(invoke, "menu").deserialize_option { |value| menu_tuple(value) }
        tray = tray(rid)
        if menu
          menu_rid, kind = menu
          tray.set_menu(menu_or_submenu(invoke.webview.resources_table, menu_rid, kind))
        else
          tray.set_menu(nil)
        end
      end

      # +set_temp_dir_path+ (plugin.rs:184-193).
      private def set_temp_dir_path(invoke)
        rid = rid_arg(invoke)
        path = argument(invoke, "path").deserialize_option { |value| path(value) }
        tray(rid).set_temp_dir_path(path)
      end

      # The commands that take a rid and an optional string
      # (plugin.rs:155-175).
      private def with_text(invoke, key)
        rid = rid_arg(invoke)
        text = argument(invoke, key).deserialize_option { |value| string(value) }
        yield tray(rid), text
      end

      # The commands that take a rid and a boolean (plugin.rs:177-215).
      private def with_flag(invoke, key)
        rid = rid_arg(invoke)
        flag = argument(invoke, key).deserialize { |value| boolean(value) }
        yield tray(rid), flag
      end

      # The tray +rid+ names in the app's table: Tauri's
      # ResourceTable::get, which downcasts or fails.
      private def tray(rid)
        resource = @app.resources_table.get(rid)
        raise Error::BadResourceId, rid unless resource.is_a?(TrayIcon)

        resource
      end

      # The Menu or Submenu +rid+ names in +table+, or the rejection Tauri
      # gives any other kind (plugin.rs:55-67).
      private def menu_or_submenu(table, rid, kind)
        expected = case kind
        when "Menu" then Menu::Menu
        when "Submenu" then Menu::Submenu
        else raise Rejection, "unexpected menu item kind"
        end
        resource = table.get(rid)
        raise Error::BadResourceId, rid unless resource.is_a?(expected)

        resource #: Menu::Menu | Menu::Submenu
      end

      # --- Reading the page's payloads, in serde's words ---

      private def argument(invoke, key)
        Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
      end

      private def rid_arg(invoke)
        argument(invoke, "rid").u32
      end

      # The +id+ of get_by_id and remove_by_id, a Rust <tt>&str</tt>: serde's
      # borrowed-string visitor names what it expected (plugin.rs:97-108).
      private def id_arg(invoke)
        argument(invoke, "id").deserialize do |value|
          value.is_a?(String) ? value : raise(Ipc::CommandItem::Mismatch.invalid_type(value, "a borrowed string"))
        end
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

      # A PathBuf, which serde reads from a string (serde de/impls.rs
      # PathBufVisitor, "path string").
      private def path(value)
        value.is_a?(String) ? value : raise(Ipc::CommandItem::Mismatch.invalid_type(value, "path string"))
      end

      # The <tt>(ResourceId, ItemKind)</tt> tuple of a menu.
      private def menu_tuple(value)
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "a tuple of size 2") unless value.is_a?(Array)
        raise mismatch("invalid length #{value.size}, expected a tuple of size 2") if value.size < 2
        raise mismatch("invalid length #{value.size}, expected fewer elements in array") if value.size > 2

        [Ipc::CommandItem.integer(value[0], "u32"), item_kind(value[1])]
      end

      # Tauri's ItemKind, a unit-variant enum: a string, or a map of the one
      # variant to +null+, as serde_json reads it.
      private def item_kind(value)
        name = nil #: String?
        content = nil #: json_value
        case value
        when String then name = value
        when Hash
          raise mismatch("invalid value: map, expected map with a single key") unless value.size == 1

          name, content = value.first
        else raise Ipc::CommandItem::Mismatch.invalid_type(value, "string or map")
        end
        name = name.to_s
        unless Menu::Plugin::ITEM_KINDS.include?(name)
          variants = Menu::Plugin::ITEM_KINDS.map { |v| "`#{v}`" }.join(", ")
          raise mismatch("unknown variant `#{name}`, expected one of #{variants}")
        end
        raise Ipc::CommandItem::Mismatch.invalid_type(content, "unit") unless content.nil?

        name
      end

      # TrayIconOptions (plugin.rs:23-35), from a map or, as serde's derive
      # also takes, a sequence of exactly its fields in order.
      private def options(value)
        hash = case value
        when Hash then value
        when Array
          if value.size < OPTION_FIELDS.size
            raise mismatch("invalid length #{value.size}, expected struct TrayIconOptions with #{OPTION_FIELDS.size} elements")
          end
          # serde_json's visit_array, once the struct has its fields
          # (serde_json 1.0.145 src/value/de.rs).
          raise mismatch("invalid length #{value.size}, expected fewer elements in array") if value.size > OPTION_FIELDS.size

          OPTION_FIELDS.zip(value).to_h
        else raise Ipc::CommandItem::Mismatch.invalid_type(value, "struct TrayIconOptions")
        end
        Options.new(
          id: optional(hash, "id") { |v| string(v) },
          menu: optional(hash, "menu") { |v| menu_tuple(v) },
          icon: optional(hash, "icon") { |v| JsImage.deserialize(v) },
          tooltip: optional(hash, "tooltip") { |v| string(v) },
          title: optional(hash, "title") { |v| string(v) },
          temp_dir_path: optional(hash, "tempDirPath") { |v| path(v) },
          icon_as_template: optional(hash, "iconAsTemplate") { |v| boolean(v) },
          menu_on_left_click: optional(hash, "menuOnLeftClick") { |v| boolean(v) },
          show_menu_on_left_click: optional(hash, "showMenuOnLeftClick") { |v| boolean(v) }
        )
      end

      # The field +key+ of +hash+ read with the block, or +nil+ when it is
      # missing or null, as serde reads an Option.
      private def optional(hash, key)
        value = hash[key]
        value.nil? ? nil : yield(value)
      end
    end
  end
end

# SPDX-SnippetEnd
