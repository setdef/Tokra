# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Plugins
    # Log is a module (not class) to allow VERSION in version.rb.
    # Log::Builder#build makes the plugin.
    module Log
      # Version of the tokra-log gem.
      VERSION = "0.0.1.pre.1"
    end
  end
end
