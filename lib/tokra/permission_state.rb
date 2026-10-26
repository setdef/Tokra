# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PermissionState adapted from tauri crates/tauri/src/plugin.rs:1012-1045

module Tokra
  # Whether the user lets the app use something only they can allow.
  #
  # Some features ask the user first: notifications, the camera, the
  # location. A plugin that guards one reports where the user stands, and
  # the frontend decides whether to ask, explain, or give up.
  #
  # PermissionState names the four answers Tauri's plugins share. Prompt
  # is the default. Each serializes as its name in the frontend's words:
  # +granted+, +denied+, +prompt+, or +prompt-with-rationale+.
  #
  # Mirrors Tauri's <tt>tauri::plugin::PermissionState</tt>
  # (plugin.rs:1012-1045).
  #
  # === Examples
  #
  #   Tokra::PermissionState::Granted.to_s     #=> "granted"
  #   JSON.generate(Tokra::PermissionState::Prompt)  #=> "\"prompt\""
  class PermissionState < Data.define(:name)
    ##
    # Permission access has been granted.
    Granted = new(name: "granted")
    # Permission access has been denied.
    Denied = new(name: "denied")
    # Permission must be requested.
    Prompt = new(name: "prompt")
    # Permission must be requested, but you must explain to the user why
    # your app needs that permission. Android only.
    PromptWithRationale = new(name: "prompt-with-rationale")

    # The default state, Prompt (plugin.rs:1021-1022).
    #
    # === Example
    #
    #   Tokra::PermissionState.default  #=> Tokra::PermissionState::Prompt
    def self.default
      Prompt
    end

    # The state as Tauri displays it: +granted+, +denied+, +prompt+, or
    # +prompt-with-rationale+ (plugin.rs:1027-1036).
    #
    # === Example
    #
    #   Tokra::PermissionState::Denied.to_s  #=> "denied"
    def to_s
      name
    end

    # The state as a JSON string, as Tauri serializes it
    # (plugin.rs:1038-1045).
    #
    # === Example
    #
    #   Tokra::PermissionState::Granted.to_json  #=> "\"granted\""
    def to_json(state = nil)
      text = name
      state ? text.to_json(state) : text.to_json
    end
  end
end

# SPDX-SnippetEnd
