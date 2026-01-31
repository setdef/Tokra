# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Config structure adapted from tauri-utils/src/config.rs

module Tokra
  # Application configuration
  #
  # See tauri-utils/src/config.rs Config struct
  Config = Data.define(:identifier, :product_name, :version)
end

# SPDX-SnippetEnd
