# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "tmpdir"

# Tests for Tokra::Image.
class TestImage < Minitest::Test
  def test_from_bytes_decodes_png
    image = Tokra::Image.from_bytes(File.binread(fixture_path("2x2.png")))

    assert_equal 2, image.width, "should decode PNG width"
    assert_equal 2, image.height, "should decode PNG height"
    assert_equal File.binread(fixture_path("2x2_rgba.bin")), image.rgba,
      "decoded RGBA should match the known raw pixels"
  end

  def test_from_bytes_decodes_ico
    image = Tokra::Image.from_bytes(File.binread(fixture_path("2x2.ico")))

    assert_equal 2, image.width, "should decode ICO width"
    assert_equal File.binread(fixture_path("2x2_rgba.bin")), image.rgba,
      "decoded RGBA should match the known raw pixels"
  end

  def test_from_bytes_raises_error_image_for_undecodable_bytes
    error = assert_raises(Tokra::Error::Image) { Tokra::Image.from_bytes("garbage") }
    assert_match(/\Afailed to process image/, error.message,
      "message should keep Tauri's failed-to-process-image prefix")
  end

  def test_from_path_decodes_file
    image = Tokra::Image.from_path(fixture_path("2x2.png"))

    assert_equal 2, image.height, "should decode the file at path"
  end

  # Tauri's from_path returns Error::Io, whose message is the io::Error's
  # Display: the OS's text for the raw error code, then " (os error N)"
  # (Rust core io/error.rs:520-526). Windows formats the Win32 code with
  # FormatMessageW (std sys/io/error/windows.rs:98-143).
  def test_from_path_raises_error_io_for_missing_file
    error = assert_raises(Tokra::Error::Io) { Tokra::Image.from_path(fixture_path("missing.png")) }

    expected = if Gem.win_platform?
      "The system cannot find the file specified. (os error 2)"
    else
      "No such file or directory (os error 2)"
    end
    assert_equal expected, error.message
  end

  # Unix opens a directory and fails to read it; Windows refuses to open
  # one without FILE_FLAG_BACKUP_SEMANTICS (std sys/fs/windows.rs:314).
  def test_from_path_raises_error_io_for_a_directory
    error = assert_raises(Tokra::Error::Io) { Tokra::Image.from_path(fixture_path("")) }

    expected = Gem.win_platform? ? "Access is denied. (os error 5)" : "Is a directory (os error 21)"
    assert_equal expected, error.message
  end

  def test_from_path_raises_error_io_for_an_unreadable_file
    skip "Windows has no POSIX file modes" if Gem.win_platform?
    skip "root reads any file" if Process.uid.zero?

    Dir.mktmpdir do |dir|
      path = File.join(dir, "unreadable.png")
      File.binwrite(path, File.binread(fixture_path("2x2.png")))
      File.chmod(0o000, path)
      error = assert_raises(Tokra::Error::Io) { Tokra::Image.from_path(path) }

      assert_equal "Permission denied (os error 13)", error.message
    end
  end

  # Rust cannot hand a path with a NUL byte to the OS, so std::fs::read
  # fails with an io::Error where Ruby's File.binread raises ArgumentError
  # (std sys/helpers/small_c_string.rs:13-14; on Windows,
  # sys/pal/windows/mod.rs:99-104).
  # Tauri's from_path takes any AsRef<Path>.
  def test_from_path_reads_a_pathname
    image = Tokra::Image.from_path(Pathname(fixture_path("2x2.png")))

    assert_equal 2, image.width, "should read the file a Pathname names"
  end

  # A read that blocks releases the GVL, so it stops only its own thread.
  # The reader opens a FIFO that only the main thread can write; the main
  # thread can write it only while the reader blocks without the GVL.
  # Holding it deadlocks the process, so the scenario runs in a child, and
  # a child that never finishes is the failure.
  def test_from_path_releases_the_gvl_while_the_read_blocks
    skip "Windows has no FIFOs" if Gem.win_platform?

    output = read_fifo_in_child("Tokra::Image.from_path(fifo).width")

    assert_equal "2", output, "the main thread should write the FIFO while the reader waits"
  end

  # std's read, which from_path makes only after Ruby's fails, releases
  # the GVL too: a failing open on a slow file system must not stop the
  # main thread either.
  def test_std_read_releases_the_gvl_while_the_read_blocks
    skip "Windows has no FIFOs" if Gem.win_platform?

    output = read_fifo_in_child("Tokra::Native.fs_read(fifo).bytesize")

    assert_equal File.size(fixture_path("2x2.png")).to_s, output,
      "the main thread should write the FIFO while std's read waits"
  end

  # Ruby reads the file, so Thread#raise ends a read that blocks, as it
  # ends any of Ruby's. std's read, which retries interrupted calls, would
  # run until the FIFO was written, and nothing writes it here: the child
  # would never finish.
  def test_from_path_is_ended_by_thread_raise_while_the_read_blocks
    skip "Windows has no FIFOs" if Gem.win_platform?

    script = <<~RUBY
      require "tokra"
      require "tmpdir"
      Dir.mktmpdir do |dir|
        fifo = File.join(dir, "image.png")
        File.mkfifo(fifo)
        reader = Thread.new do
          Tokra::Image.from_path(fifo)
        rescue => e
          e.message
        end
        Thread.pass until reader.status == "sleep"
        reader.raise("stopped")
        print reader.value
      end
    RUBY
    output = run_child(script, timeout: 30)

    assert_equal "stopped", output, "Thread#raise should end the blocked read"
  end

  def test_from_path_raises_error_io_for_a_nul_byte
    error = assert_raises(Tokra::Error::Io) { Tokra::Image.from_path("a\0b.png") }

    expected = Gem.win_platform? ? "strings passed to WinAPI cannot contain NULs" : "file name contained an unexpected NUL byte"
    assert_equal expected, error.message
  end

  def test_stores_rgba_data
    rgba = "\xFF\x00\x00\xFF".b # 1x1 red pixel
    image = Tokra::Image.new(rgba:, width: 1, height: 1)

    assert_equal rgba, image.rgba, "should store rgba data"
    assert_equal 1, image.width, "should store width"
    assert_equal 1, image.height, "should store height"
  end

  def test_positional_constructor
    rgba = "\xFF\x00\x00\xFF".b
    image = Tokra::Image.new(rgba, 1, 1)

    assert_equal rgba, image.rgba, "positional args should work"
  end

  def test_name_returns_identifier
    image = Tokra::Image.new(rgba: "", width: 0, height: 0)
    assert_equal "Tokra::Image", image.name
  end

  def test_close_returns_nil
    image = Tokra::Image.new(rgba: "", width: 0, height: 0)
    assert_nil image.close
  end

  def test_includes_resource_module
    assert_includes Tokra::Image.ancestors, Tokra::Resource
  end

  def test_integration_with_resource_table
    table = Tokra::ResourceTable.new
    rgba = "\xFF\x00\x00\xFF\x00\xFF\x00\xFF".b # 2x1 image
    image = Tokra::Image.new(rgba:, width: 2, height: 1)

    rid = table.add(image)
    retrieved = table.get(rid)

    assert_same image, retrieved, "ResourceTable should store and retrieve Image"
    assert_equal 2, retrieved.width
  end

  def test_round_trip_file_io
    require "digest"
    require "tempfile"

    # Load from fixture file on disk
    fixture_path = File.expand_path("fixtures/2x2_rgba.bin", __dir__)
    loaded_rgba = File.binread(fixture_path)
    image = Tokra::Image.new(rgba: loaded_rgba, width: 2, height: 2)

    # Store in ResourceTable
    table = Tokra::ResourceTable.new
    rid = table.add(image)

    # Retrieve from ResourceTable
    retrieved = table.get(rid)

    # Write to new temp file
    output_file = Tempfile.new(["output", ".rgba"])
    begin
      output_file.binmode
      output_file.write(retrieved.rgba)
      output_file.close

      # Compare hashes
      original_hash = Digest::SHA256.file(fixture_path)
      output_hash = Digest::SHA256.file(output_file.path)

      assert_equal original_hash.hexdigest, output_hash.hexdigest,
        "Retrieved image data should match original file exactly"
    ensure
      output_file.close!
    end
  end

  # Returns the absolute path of a fixture file.
  # Runs +read+ in a reader thread of a child Ruby, on a FIFO the child's
  # main thread then writes the 2x2 PNG into, and returns what +read+
  # returned, or nil when the child deadlocked.
  private def read_fifo_in_child(read)
    script = <<~RUBY
      require "tokra"
      require "tmpdir"
      Dir.mktmpdir do |dir|
        fifo = File.join(dir, "image.png")
        File.mkfifo(fifo)
        reader = Thread.new { #{read} }
        File.binwrite(fifo, File.binread(#{fixture_path('2x2.png').dump}))
        print reader.value
      end
    RUBY
    run_child(script, timeout: 30)
  end

  # Runs +script+ in a child Ruby and returns what it printed, or nil when
  # it did not finish within +timeout+ seconds (it is then killed).
  private def run_child(script, timeout:)
    IO.popen([RbConfig.ruby, "-e", script], err: [:child, :out]) do |child|
      output = nil
      collector = Thread.new { output = child.read }
      next output if collector.join(timeout)

      Process.kill(:KILL, child.pid)
      collector.join
      nil
    end
  end

  private def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end
end
