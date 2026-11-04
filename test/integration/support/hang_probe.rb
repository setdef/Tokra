# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fiddle"
require "rbconfig"

# What RealApp learns about a hung fixture before it kills it, on
# Windows, where the hangs are seen only in CI and cannot be watched.
#
# Run 41759900272 hung multiwindow_routing on Windows after "main" heard
# CloseRequested: main was never Destroyed and the app never exited, and
# its output alone cannot say why. Three things can: whether each of the
# fixture's windows still exists, which says whether tao's DestroyWindow
# ran; whether the thread that made them takes a sent message, which says
# whether the main thread still pumps or is blocked in a call; and each
# thread's stack, which says where. The probe looks from the test
# process, so it adds no thread or timer to the fixture. It does touch
# the hung app: each window is sent a WM_NULL, which a window ignores,
# and the debugger (cdb -pv) suspends the app's threads while it reads
# their stacks, then resumes them.
#
# Each section has its own bound (SEND_TIMEOUT per window, and a limit
# on each command it runs), and one that fails or runs out loses only
# itself: the rest of the report still arrives.
module HangProbe
  # What the probe found about process +pid+, as text, or +nil+ off
  # Windows.
  def self.call(pid)
    return nil unless RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)

    Win32.report(pid)
  end

  # The probe's Win32 half. The signatures follow windows-sys 0.59.0
  # (Win32/UI/WindowsAndMessaging/mod.rs).
  module Win32
    WM_NULL = 0x0000
    SMTO_ABORTIFHUNG = 0x0002
    # Milliseconds a window's thread gets to take the WM_NULL.
    SEND_TIMEOUT = 1000
    # The most windows the probe describes, each taking up to
    # SEND_TIMEOUT, so the windows section is bounded too.
    MAX_WINDOWS = 64
    # Where the Windows SDK puts the console debugger on an x64 runner.
    CDB = File.join(ENV.fetch("ProgramFiles(x86)", "C:/Program Files (x86)"), "Windows Kits/10/Debuggers/x64/cdb.exe")
    # Seconds the debugger gets to print every thread's stack.
    CDB_TIMEOUT = 60
    # Seconds PowerShell gets to list the threads and child processes.
    POWERSHELL_TIMEOUT = 30
    # Seconds a command's output gets to drain once the command is gone.
    DRAIN = 5

    # Each section, or how it failed, so one that fails loses only itself.
    def self.report(pid)
      %i[windows threads stacks].map do |section|
        __send__(section, pid)
      rescue => e
        "#{section}: probe failed: #{e.class}: #{e.message}"
      end.join("\n")
    end

    # Each top-level window of +pid+, with each child window under it,
    # whichever process that child belongs to: WebView2's are its
    # browser's.
    def self.windows(pid)
      found = top_level(pid).flat_map { |window| [[window, ""], *children(window).map { |child| [child, "  "] }] }
      lines = found.first(MAX_WINDOWS).map { |window, indent| describe(window, indent) }
      lines << "(#{found.size - MAX_WINDOWS} more not described)" if found.size > MAX_WINDOWS
      lines.empty? ? "windows: none" : "windows:\n#{lines.join("\n")}"
    end

    def self.top_level(pid)
      found = []
      visit = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T]) do |window, _|
        found << window if owner(window).last == pid
        1
      end
      fn("EnumWindows", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(visit, 0)
      found
    end

    def self.children(window)
      found = []
      visit = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T]) do |child, _|
        found << child
        1
      end
      fn("EnumChildWindows", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT)
        .call(window, visit, 0)
      found
    end

    # One line for +window+: its handle, class, title, owning thread and
    # process, whether it shows, and whether its thread took a WM_NULL.
    def self.describe(window, indent)
      thread, process = owner(window)
      visible = !fn("IsWindowVisible", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(window).zero?
      hung = !fn("IsHungAppWindow", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(window).zero?
      format("%<indent>s0x%<window>x class=%<class>p title=%<title>p thread=%<thread>d pid=%<process>d " \
        "visible=%<visible>s hung=%<hung>s answers_wm_null=%<answers>s",
        indent:, window:, class: text("GetClassNameW", window), title: text("GetWindowTextW", window), thread:,
        process:, visible:, hung:, answers: answers?(window))
    end

    # The thread and the process that made +window+.
    def self.owner(window)
      process = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
      thread = fn("GetWindowThreadProcessId", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT)
        .call(window, process)
      [thread, process[0, 4].unpack1("L")]
    end

    # Whether +window+'s thread took a WM_NULL within SEND_TIMEOUT.
    def self.answers?(window)
      result = Fiddle::Pointer.malloc(Fiddle::SIZEOF_UINTPTR_T, Fiddle::RUBY_FREE)
      !fn("SendMessageTimeoutW", [
        Fiddle::TYPE_INTPTR_T,
        Fiddle::TYPE_UINT,
        Fiddle::TYPE_UINTPTR_T,
        Fiddle::TYPE_INTPTR_T,
        Fiddle::TYPE_UINT,
        Fiddle::TYPE_UINT,
        Fiddle::TYPE_VOIDP,
      ], Fiddle::TYPE_INTPTR_T).call(window, WM_NULL, 0, 0, SMTO_ABORTIFHUNG, SEND_TIMEOUT, result).zero?
    end

    # +window+'s class name or title, through the W function +name+.
    def self.text(name, window)
      buffer = Fiddle::Pointer.malloc(256 * 2, Fiddle::RUBY_FREE)
      length = fn(name, [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        .call(window, buffer, 256)
      buffer.to_str(length * 2).force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
    end

    # Each thread of +pid+ with its state and, for a waiting thread, why,
    # and each process +pid+ started, such as WebView2's browser.
    def self.threads(pid)
      script = <<~POWERSHELL
        (Get-Process -Id #{Integer(pid)}).Threads | Sort-Object Id | ForEach-Object {
          $why = if ($_.ThreadState -eq 'Wait') { $_.WaitReason } else { '' }
          "thread $($_.Id) $($_.ThreadState) $why cpu=$($_.TotalProcessorTime.TotalMilliseconds)ms"
        }
        Get-CimInstance Win32_Process -Filter "ParentProcessId=#{Integer(pid)}" | ForEach-Object {
          "child $($_.ProcessId) $($_.Name)"
        }
      POWERSHELL
      command = ["powershell", "-NoProfile", "-NonInteractive", "-Command", script]
      "threads:\n#{capture(command, POWERSHELL_TIMEOUT)}"
    end

    # Every thread's stack, from the console debugger attached
    # noninvasively (-pv), which suspends the threads while it reads them
    # and resumes them as it detaches, when the runner has one. Without
    # symbols each frame names the nearest export, which is enough to
    # tell GetMessageW from DestroyWindow or SendMessageW.
    def self.stacks(pid)
      return "stacks: no debugger at #{CDB}" unless File.exist?(CDB)

      "stacks:\n#{capture([CDB, '-pv', '-p', Integer(pid).to_s, '-c', '~*kn 40; q'], CDB_TIMEOUT)}"
    end

    # What +command+ printed within +seconds+, read line by line as
    # RealApp.launch reads a fixture, so what it printed before it was
    # killed survives. However this returns, raised through included, the
    # command is not left running, since cdb would stay attached.
    def self.capture(command, seconds)
      reader, writer = IO.pipe
      begin
        child = Process.spawn(*command, out: writer, err: writer, in: File::NULL)
      ensure
        writer.close
      end
      output = +""
      drained = Thread.new { reader.each_line { |line| output << line } }
      drained.report_on_exception = false
      waiter = Process.detach(child)
      unless waiter.join(seconds)
        kill(child)
        output << "(killed after #{seconds} s)\n"
      end
      drained.join(DRAIN)
      output.dup
    ensure
      if waiter&.alive?
        kill(child)
        waiter.join(DRAIN)
      end
      reader&.close
    end

    # Kills +pid+, ignoring a process that already ended, as
    # RealApp.signal does.
    def self.kill(pid)
      Process.kill(:KILL, pid)
    rescue Errno::ESRCH
      nil
    end

    def self.fn(name, args, ret)
      @user32 ||= Fiddle.dlopen("user32")
      Fiddle::Function.new(@user32[name], args, ret)
    end
  end
end
