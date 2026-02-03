# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Image structure adapted from tauri/crates/tauri/src/image/mod.rs

module Tokra
  # An RGBA image in row-major order from top to bottom.
  #
  # Stores raw pixel data as bytes. Each pixel is 4 bytes (RGBA).
  # Total bytes should equal +width * height * 4+.
  #
  # Mirrors Tauri's +Image<'a>+ struct. This class includes the Resource
  # module for ResourceTable compatibility.
  #
  # Example:
  #   rgba = "\xFF\x00\x00\xFF".b  # 1x1 red pixel
  #   image = Tokra::Image.new(rgba: rgba, width: 1, height: 1)
  #   rid = table.add(image)
  #
  class Image < Data.define(:rgba, :width, :height)
    include Resource
  end
end

# SPDX-SnippetEnd
