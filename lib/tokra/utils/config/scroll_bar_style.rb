# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: ScrollBarStyle adapted from tauri-utils src/config.rs:1620-1633
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The scroll bars a config's window asks for.
      #
      # A config is one file for every platform, so it can name a style
      # only one platform draws: <tt>"fluentOverlay"</tt>, Windows' thin
      # floating scroll bars, reads on macOS and Linux too. That is why
      # this is a type of its own, with both styles everywhere, apart from
      # Tokra::ScrollBarStyle, the webview's, which has FluentOverlay only
      # on Windows. A window built from the config takes Default wherever
      # its platform lacks the style, as Tauri's does
      # (tauri-runtime src/webview.rs:431-436).
      #
      # These two are the only styles, so ScrollBarStyle.new is private.
      #
      # Mirrors Tauri's <tt>tauri_utils::config::ScrollBarStyle</tt>
      # (config.rs:1620-1633).
      #
      # === Example
      #
      #   window.scroll_bar_style  #=> Tokra::Utils::Config::ScrollBarStyle::Default
      class ScrollBarStyle < Data.define(:name)
        extend ClosedEnum

        ##
        # The browser's own scroll bars.
        Default = new(name: "Default")
        # Fluent UI's overlay scroll bars. Windows only; WebView2 125.0.2535.41
        # or later draws them.
        FluentOverlay = new(name: "FluentOverlay")

        # Reads +value+, a JSON value, as serde reads the enum: a unit
        # variant renamed camelCase.
        def self.deserialize(value) # :nodoc:
          (Ipc::Serde.unit_variant(value, %w[default fluentOverlay]) == "default") ? Default : FluentOverlay
        end

        close
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
