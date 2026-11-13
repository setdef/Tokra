# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PluginApi adapted from tauri/crates/tauri/src/plugin.rs:147-179

module Tokra
  # What a plugin's setup block gets beside the app handle.
  #
  # A plugin is configured in the app's config, under its own name in
  # +plugins+, and its setup runs once the app exists. Setup wants that
  # slice already read into the plugin's own config type, not raw JSON
  # to pick apart.
  #
  # The app hands a Plugin::Builder's setup block one of these: the
  # handle, the plugin's name, and the slice, read by the config type
  # the builder was given (+nil+ for a plugin that takes none).
  #
  # Use it to read your plugin's settings while it sets up.
  #
  # Mirrors Tauri's <tt>PluginApi<R, C></tt> (plugin.rs:147-179). Its
  # +scope+, the ACL's global scope, waits for capabilities.
  #
  # === Example
  #
  #   Tokra::Plugin::Builder.new("store", config: StoreConfig)
  #     .setup { |app, api| app.manage(Store.new(api.config.path)) }
  #     .build
  class PluginApi < Data.define(:app, :config, :name)
    ##
    # :attr_reader: app
    # The AppHandle of the app the plugin joins (plugin.rs:163-166).

    ##
    # :attr_reader: config
    # The plugin's config, read from its slice of the app config's
    # +plugins+ (plugin.rs:158-161).

    ##
    # :attr_reader: name
    # The plugin's name, the key of its slice.
  end
end

# SPDX-SnippetEnd
