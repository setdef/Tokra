# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2018-2023 the Deno authors, 2019-2024 Tauri Programme

module Tokra
  # Table for managing resources by integer ID.
  #
  # Resources are stored and retrieved by random u32 ID. Each Webview and
  # Window has its own ResourceTable. Full implementation in Phase 2.1.
  #
  # Ported from Deno's resource system via Tauri.
  class ResourceTable
    # Creates an empty resource table.
    def initialize
      @index = {}
    end

    # Checks if a resource ID exists in this table.
    #
    # This is a placeholder; Phase 2.1 adds add/get/take/close.
    def has?(rid)
      @index.key?(rid)
    end
  end
end

# SPDX-SnippetEnd
