# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AppHandle structure adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Handle to the running application, safe to pass between Ractors.
  #
  # Provides access to application state and control methods.
  class AppHandle
    # Creates a new AppHandle with the given configuration.
    #
    # This is called internally by App and should not be called directly.
    def initialize(config)
      @config = config
    end

    # Returns the application configuration.
    def config
      @config
    end

    # Requests application exit with optional exit code.
    #
    # Currently calls Kernel.exit directly.
    # Will signal native event loop when wired up.
    def exit(code = 0)
      Kernel.exit(code)
    end
  end
end

# SPDX-SnippetEnd
