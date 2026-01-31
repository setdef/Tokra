# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Api exposed to plugins during initialization.
  #
  # Wraps the app handle and plugin-specific configuration.
  # Mirrors Tauri's PluginApi<R, C> struct.
  #
  # == Example
  #
  #   def setup(api)
  #     @app = api.app
  #     @logger = Logger.new(api.config[:path])
  #   end
  #
  # == Future
  #
  # May include permission scopes when implemented.
  PluginApi = Data.define(:app, :config, :name)
end
