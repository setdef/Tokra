# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AppManager structure adapted from tauri/crates/tauri/src/manager/mod.rs

module Tokra
  # Internal manager for application state (minimal MVP subset of Tauri's AppManager).
  #
  # See tauri/src/manager/mod.rs AppManager
  class AppManager < Data.define(:config, :webviews, :windows, :plugins, :invoke_key)
    # Creates a new AppManager.
    #
    # +plugins+ defaults to an empty PluginStore, mirroring Tauri's
    # AppManager which always owns its plugin store. +invoke_key+
    # defaults to a fresh per-app key (Tokra.generate_invoke_key),
    # mirroring the invoke_key member Tauri's AppManager holds
    # (manager/mod.rs).
    def self.new(config:, webviews:, windows:, plugins: PluginStore.new, invoke_key: Tokra.generate_invoke_key)
      super
    end
  end
end

# SPDX-SnippetEnd
