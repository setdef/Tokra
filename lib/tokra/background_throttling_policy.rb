# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: BackgroundThrottlingPolicy adapted from tauri-utils/src/config.rs

module Tokra
  # How a webview's page runs while nobody can see it.
  #
  # A browser saves power in a tab you have hidden: it slows the page's
  # timers, and after about five minutes it suspends the page until you
  # show it again. A desktop app often hides a window that still has work
  # to do, such as a player or a sync loop, and finds it frozen. Pass one
  # of these to WebviewWindowBuilder#background_throttling to choose.
  #
  # These three are the only policies, as in Tauri's enum, so
  # BackgroundThrottlingPolicy.new is private.
  #
  # Mirrors Tauri's <tt>BackgroundThrottlingPolicy</tt> (tauri-utils
  # src/config.rs:1559-1570).
  #
  # === Example
  #
  #   builder.background_throttling(Tokra::BackgroundThrottlingPolicy::Disabled)
  class BackgroundThrottlingPolicy < Data.define(:name)
    extend ClosedEnum

    ##
    # The page runs as if it were in sight.
    Disabled = new(name: "Disabled")
    # The page stops running while it is out of sight, as a browser
    # usually does when you set no policy.
    Suspend = new(name: "Suspend")
    # The page runs slower while it is out of sight, but never stops.
    Throttle = new(name: "Throttle")

    # Reads +value+, a JSON value, as the derived Deserialize reads it: a
    # unit variant renamed camelCase, <tt>"disabled"</tt>,
    # <tt>"suspend"</tt>, or <tt>"throttle"</tt> (config.rs:1559-1570).
    def self.deserialize(value) # :nodoc:
      policies = { "disabled" => Disabled, "suspend" => Suspend, "throttle" => Throttle }
      policies.fetch(Ipc::Serde.unit_variant(value, policies.keys))
    end

    close
  end
end

# SPDX-SnippetEnd
