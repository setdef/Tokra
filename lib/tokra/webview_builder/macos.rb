# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles allow_link_preview only for macOS (webview/mod.rs:1196-1203;
# webview_window.rs:857-862), so it exists only there (ADR 011; plan 052,
# decision e1-6).
return unless Tokra::App.os_name == "macos"

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: The macOS webview rows adapted from tauri/crates/tauri/src/webview/mod.rs,
#                      webview/webview_window.rs, and tauri-runtime-wry/src/lib.rs

module Tokra
  class WebviewBuilder # :nodoc:
    # Tauri's WebviewBuilder::allow_link_preview (webview/mod.rs:1196-1203;
    # lib.rs:4930-4931).
    def allow_link_preview(allow_link_preview)
      flag(:allow_link_preview, allow_link_preview)
    end
  end

  class WebviewWindowBuilder
    # Shows a preview of a link's page when the person presses hard on the
    # link, or turns it off, and returns the builder. On by default, as in
    # Safari. Defined only on macOS, as in Tauri.
    #
    # Mirrors Tauri's WebviewWindowBuilder::allow_link_preview
    # (webview_window.rs:857-862), which wry turns into WKWebView's
    # allowsLinkPreview (tauri-runtime-wry lib.rs:4930-4931).
    #
    # === Example
    #
    #   builder.allow_link_preview(false)
    def allow_link_preview(allow_link_preview)
      webview_row { |rows| rows.allow_link_preview(allow_link_preview) }
    end
  end
end

# SPDX-SnippetEnd
