# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: UserAttentionType adapted from tauri-runtime/src/lib.rs;
#                      its internally tagged reading is serde 1.0.228's

module Tokra
  # How urgently Window#request_user_attention asks for attention.
  #
  # These two are the only kinds, as in Tauri's enum, so
  # UserAttentionType.new is private.
  #
  # Mirrors Tauri's <tt>tauri::UserAttentionType</tt> (tauri-runtime
  # src/lib.rs:80-85), as tao describes each kind (tao 0.34.5
  # src/window.rs:1521-1533).
  #
  # === Example
  #
  #   window.request_user_attention(Tokra::UserAttentionType::Informational)
  class UserAttentionType < Data.define(:name)
    extend ClosedEnum

    ##
    # On macOS, bounces the Dock icon until the app is in focus; on
    # Windows, flashes both the window and the taskbar button until the
    # app is in focus.
    Critical = new(name: "Critical")
    # On macOS, bounces the Dock icon once; on Windows, flashes the
    # taskbar button until the app is in focus.
    Informational = new(name: "Informational")

    # The kind a command argument names, as the derived Deserialize reads
    # it: internally tagged on <tt>"type"</tt> (tauri-runtime
    # src/lib.rs:79-81). A map's other keys are ignored; a sequence holds
    # the tag and nothing after it, since a unit variant reads the rest as
    # an empty sequence (serde private/de.rs:1092-1101, 2983-2996).
    def self.deserialize(value) # :nodoc:
      name, rest = Ipc::Serde.internally_tagged(value, "type", "UserAttentionType", %w[Critical Informational])
      if rest.is_a?(Array) && !rest.empty?
        raise Ipc::CommandItem::Mismatch, "invalid length #{rest.size}, expected 0 elements in sequence"
      end

      (name == "Critical") ? Critical : Informational
    end

    close
  end
end

# SPDX-SnippetEnd
