# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Plugins
    # Clipboard is a module (not class) to allow VERSION in version.rb.
    # The actual plugin is Clipboard::Plugin.
    module Clipboard
      # Version of the tokra-clipboard gem.
      VERSION = "0.0.1.pre.1"
    end
  end
end
