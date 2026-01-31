# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: UriSchemeContext adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Context passed to URI scheme protocol handlers.
  #
  # Provides access to the app handle and webview label that initiated
  # the request. Mirrors Tauri's UriSchemeContext.
  UriSchemeContext = Data.define(:app_handle, :webview_label)
end

# SPDX-SnippetEnd
