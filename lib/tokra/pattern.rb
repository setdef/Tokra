# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Pattern adapted from tauri src/pattern.rs at vendor/tauri 9f0306fbc
#++

module Tokra
  # The pattern your app's pages invoke through, as the app runs it.
  #
  # A config names a pattern in <tt>app.security.pattern</tt>, and
  # Tokra.generate_context turns it into this: what the running app uses
  # to route each invoke, and what its pages read as
  # <tt>__TAURI_PATTERN__</tt>.
  #
  # Tokra builds the brownfield pattern, where pages invoke directly. A
  # config's isolation pattern reads as Brownfield until an isolation plan
  # builds the isolation app's frame and keys, as Tauri without its
  # <tt>isolation</tt> feature does (tauri-codegen src/context.rs:354-359;
  # plan 054, decision 21).
  #
  # Mirrors Tauri's <tt>tauri::Pattern</tt> (pattern.rs).
  #
  # === Example
  #
  #   Tokra.generate_context.pattern  #=> #<data Tokra::Pattern::Brownfield>
  module Pattern
    # Pages invoke your commands directly.
    Brownfield = Data.define
  end
end

#--
# SPDX-SnippetEnd
#++
