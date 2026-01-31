# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PhysicalPosition adapted from tauri-runtime dpi module

module Tokra
  # A position in physical (pixel) coordinates.
  #
  # Maps to Tauri's +dpi::PhysicalPosition<f64>+.
  class PhysicalPosition < Data.define(:x, :y)
  end
end

# SPDX-SnippetEnd
