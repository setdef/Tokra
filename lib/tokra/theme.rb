# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Theme adapted from tauri-utils/src/lib.rs

module Tokra
  # A window's light or dark appearance.
  #
  # Window#theme answers the one the window shows, and Window#set_theme
  # picks one, or +nil+ to follow the system's. These two are the only
  # themes, as in Tauri's enum, so Theme.new is private.
  #
  # Mirrors Tauri's <tt>tauri::Theme</tt> (tauri-utils src/lib.rs:218-226).
  #
  # === Example
  #
  #   window.set_theme(Tokra::Theme::Dark)
  #   window.theme  #=> #<data Tokra::Theme name="Dark">
  class Theme < Data.define(:name)
    extend ClosedEnum

    ##
    # Light theme.
    Light = new(name: "Light")
    # Dark theme.
    Dark = new(name: "Dark")

    # The theme a command argument names, as Tauri's own Deserialize reads
    # it: <tt>"dark"</tt> in any case is Dark, and any other string Light
    # (tauri-utils src/lib.rs:238-250). Anything but a string raises
    # Ipc::CommandItem::Mismatch, <tt>expected a string</tt>.
    def self.deserialize(value) # :nodoc:
      (Ipc::Serde.string(value).downcase == "dark") ? Dark : Light
    end

    # The theme as JSON, as Tauri's Serialize writes its Display text:
    # <tt>"light"</tt> or <tt>"dark"</tt> (tauri-utils src/lib.rs:228-236,
    # 252-260). Window#theme answers it to the page this way.
    #
    # === Example
    #
    #   Tokra::Theme::Dark.to_json  #=> "\"dark\""
    def to_json(state = nil)
      json = as_json
      state ? json.to_json(state) : json.to_json
    end

    # The theme as a JSON value, as #to_json writes it.
    def as_json # :nodoc:
      name.downcase
    end

    close
  end
end

# SPDX-SnippetEnd
