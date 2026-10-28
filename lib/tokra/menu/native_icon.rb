# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: NativeIcon adapted from tauri/crates/tauri/src/menu/mod.rs

module Tokra
  module Menu
    # One of macOS's own images, for a menu item or a submenu.
    #
    # An IconMenuItem or a Submenu can show an image the app draws, a
    # Tokra::Image, or one macOS already has, such as its padlock or its
    # trash can. These 56 are the only ones, as in Tauri's enum, so
    # NativeIcon.new is private. Windows and Linux show no native icon.
    #
    # Mirrors Tauri's <tt>tauri::menu::NativeIcon</tt> (menu/mod.rs:355-474).
    #
    # === Example
    #
    #   Tokra::Menu::IconMenuItem.with_native_icon(app, "Lock", true, Tokra::Menu::NativeIcon::LockLocked, nil)
    class NativeIcon < Data.define(:name)
      extend ClosedEnum

      ##
      # An add item template image.
      Add = new(name: "Add")
      # Advanced preferences toolbar icon for the preferences window.
      Advanced = new(name: "Advanced")
      # A Bluetooth template image.
      Bluetooth = new(name: "Bluetooth")
      # Bookmarks image suitable for a template.
      Bookmarks = new(name: "Bookmarks")
      # A caution image.
      Caution = new(name: "Caution")
      # A color panel toolbar icon.
      ColorPanel = new(name: "ColorPanel")
      # A column view mode template image.
      ColumnView = new(name: "ColumnView")
      # A computer icon.
      Computer = new(name: "Computer")
      # An enter full-screen mode template image.
      EnterFullScreen = new(name: "EnterFullScreen")
      # Permissions for all users.
      Everyone = new(name: "Everyone")
      # An exit full-screen mode template image.
      ExitFullScreen = new(name: "ExitFullScreen")
      # A cover flow view mode template image.
      FlowView = new(name: "FlowView")
      # A folder image.
      Folder = new(name: "Folder")
      # A burnable folder icon.
      FolderBurnable = new(name: "FolderBurnable")
      # A smart folder icon.
      FolderSmart = new(name: "FolderSmart")
      # A link template image.
      FollowLinkFreestanding = new(name: "FollowLinkFreestanding")
      # A font panel toolbar icon.
      FontPanel = new(name: "FontPanel")
      # A go back template image.
      GoLeft = new(name: "GoLeft")
      # A go forward template image.
      GoRight = new(name: "GoRight")
      # Home image suitable for a template.
      Home = new(name: "Home")
      # An iChat Theater template image.
      IChatTheater = new(name: "IChatTheater")
      # An icon view mode template image.
      IconView = new(name: "IconView")
      # An information toolbar icon.
      Info = new(name: "Info")
      # A template image used to denote invalid data.
      InvalidDataFreestanding = new(name: "InvalidDataFreestanding")
      # A generic left-facing triangle template image.
      LeftFacingTriangle = new(name: "LeftFacingTriangle")
      # A list view mode template image.
      ListView = new(name: "ListView")
      # A locked padlock template image.
      LockLocked = new(name: "LockLocked")
      # An unlocked padlock template image.
      LockUnlocked = new(name: "LockUnlocked")
      # A horizontal dash, for use in menus.
      MenuMixedState = new(name: "MenuMixedState")
      # A check mark template image, for use in menus.
      MenuOnState = new(name: "MenuOnState")
      # A MobileMe icon.
      MobileMe = new(name: "MobileMe")
      # A drag image for multiple items.
      MultipleDocuments = new(name: "MultipleDocuments")
      # A network icon.
      Network = new(name: "Network")
      # A path button template image.
      Path = new(name: "Path")
      # General preferences toolbar icon for the preferences window.
      PreferencesGeneral = new(name: "PreferencesGeneral")
      # A Quick Look template image.
      QuickLook = new(name: "QuickLook")
      # A refresh template image.
      RefreshFreestanding = new(name: "RefreshFreestanding")
      # A refresh template image.
      Refresh = new(name: "Refresh")
      # A remove item template image.
      Remove = new(name: "Remove")
      # A reveal contents template image.
      RevealFreestanding = new(name: "RevealFreestanding")
      # A generic right-facing triangle template image.
      RightFacingTriangle = new(name: "RightFacingTriangle")
      # A share view template image.
      Share = new(name: "Share")
      # A slideshow template image.
      Slideshow = new(name: "Slideshow")
      # A badge for a smart item.
      SmartBadge = new(name: "SmartBadge")
      # Small green indicator, similar to iChat's available image.
      StatusAvailable = new(name: "StatusAvailable")
      # Small clear indicator.
      StatusNone = new(name: "StatusNone")
      # Small yellow indicator, similar to iChat's idle image.
      StatusPartiallyAvailable = new(name: "StatusPartiallyAvailable")
      # Small red indicator, similar to iChat's unavailable image.
      StatusUnavailable = new(name: "StatusUnavailable")
      # A stop progress template image.
      StopProgressFreestanding = new(name: "StopProgressFreestanding")
      # A stop progress button template image.
      StopProgress = new(name: "StopProgress")
      # An image of the empty trash can.
      TrashEmpty = new(name: "TrashEmpty")
      # An image of the full trash can.
      TrashFull = new(name: "TrashFull")
      # Permissions for a single user.
      User = new(name: "User")
      # User account toolbar icon for the preferences window.
      UserAccounts = new(name: "UserAccounts")
      # Permissions for a group of users.
      UserGroup = new(name: "UserGroup")
      # Permissions for guests.
      UserGuest = new(name: "UserGuest")

      close
    end
  end
end

# SPDX-SnippetEnd
