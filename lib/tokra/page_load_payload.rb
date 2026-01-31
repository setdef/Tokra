# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PageLoadPayload adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Page load payload passed to on_page_load callbacks.
  #
  # Indicates whether the page load is starting or finished.
  class PageLoadPayload < Data.define(:url, :started)
    ##
    # Returns true if the page load is starting.
    def started?
      started
    end

    ##
    # Returns true if the page load is finished.
    def finished?
      !started
    end
  end
end

# SPDX-SnippetEnd
