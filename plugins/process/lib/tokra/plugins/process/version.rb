# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Plugins
    # Process is a module (not class) to allow VERSION in version.rb.
    # The actual plugin is Process::Plugin.
    module Process
      # Version of the tokra-process gem.
      VERSION = "0.0.1.pre.1"
    end
  end
end
