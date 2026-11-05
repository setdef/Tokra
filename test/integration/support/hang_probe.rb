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
# their stacks, then detaches.
#
# Run 42094852755 hung the same way, with main's thread inside
# DestroyWindow, and showed that two more things are needed: what the
# kernel says that thread waits on, which the debugger cannot show, and
# what the threads of the other processes whose windows sit in the
# fixture's tree are doing, since DestroyWindow must destroy those too.
# So the probe also asks Wait Chain Traversal for each thread's wait
# chain (WaitChains), and runs the debugger on each of those processes,
# without suspending them (owner_stacks says why).
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
    # Seconds each debugger gets to print every thread's stack: the
    # fixture's, which runs on its own, and then each other process's,
    # which all run at once.
    CDB_TIMEOUT = 60
    # Frames the debugger prints of each thread of another process that
    # owns a window in the fixture's tree. It is passed in hex, since k's
    # FrameCount is read in the debugger's radix, hex by default ("k, kb,
    # kc, kd, kp, kP, kv (Display Stack Backtrace)").
    OWNER_FRAMES = 60
    # Seconds the Ruby that walks the wait chains gets to print them.
    WAIT_CHAIN_TIMEOUT = 30
    # Seconds PowerShell gets to list the threads and child processes.
    POWERSHELL_TIMEOUT = 30
    # Seconds a command's output gets to drain once the command is gone.
    DRAIN = 5

    # Each section, or how it failed, so one that fails loses only itself.
    def self.report(pid)
      %i[windows wait_chains threads stacks owner_stacks].map do |section|
        __send__(section, pid)
      rescue => e
        "#{section}: probe failed: #{e.class}: #{e.message}"
      end.join("\n")
    end

    # Each top-level window of +pid+, with each child window under it,
    # whichever process that child belongs to: WebView2's are its
    # browser's.
    def self.windows(pid)
      found = tree(pid)
      lines = found.first(MAX_WINDOWS).map { |window, indent| describe(window, indent) }
      lines << "(#{found.size - MAX_WINDOWS} more not described)" if found.size > MAX_WINDOWS
      lines.empty? ? "windows: none" : "windows:\n#{lines.join("\n")}"
    end

    # Each top-level window of +pid+, then each child under it, each with
    # the indent windows describes it with.
    def self.tree(pid)
      top_level(pid).flat_map { |window| [[window, ""], *children(window).map { |child| [child, "  "] }] }
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
    # noninvasively (-pv), when the runner has one. Without symbols each
    # frame names the nearest export, which is enough to tell GetMessageW
    # from DestroyWindow or SendMessageW.
    #
    # Microsoft's "Noninvasive Debugging (User Mode)" says -pv suspends
    # all of the target's threads, so the stacks are of one moment. It
    # ends with qd, which "ends the debugging session and leaves any
    # user-mode target application running" ("qd (Quit and Detach)"),
    # where "q (Quit)" says that in user mode q "closes the target
    # application", which would leave owner_stacks, which runs next, no
    # tree to look at. A debugger capture kills at CDB_TIMEOUT may leave
    # the fixture suspended, which harms nothing: RealApp kills it once
    # the probe returns.
    def self.stacks(pid)
      return "stacks: no debugger at #{CDB}" unless File.exist?(CDB)

      "stacks:\n#{capture([CDB, '-pv', '-p', Integer(pid).to_s, '-c', '~*kn 40; qd'], CDB_TIMEOUT)}"
    end

    # Each thread's wait chain, from WaitChains. A synchronous wait chain
    # call can block, and Ruby can neither interrupt a native call nor
    # end while one of its threads is in one, so the walk runs in a Ruby
    # of its own, which capture kills if it runs out of time.
    def self.wait_chains(pid)
      script = "$stdout.sync = true; HangProbe::WaitChains.print_report(Integer(ARGV.fetch(0)), $stdout)"
      command = [RbConfig.ruby, "-r", File.expand_path(__FILE__), "-e", script, Integer(pid).to_s]
      "wait chains:\n#{capture(command, WAIT_CHAIN_TIMEOUT)}"
    end

    # The stacks of every other process that owns a window in +pid+'s
    # tree, such as WebView2's browser and GPU processes, whose windows
    # DestroyWindow must destroy too. Each starts with the threads that
    # own those windows, so a debugger that runs out of time has printed
    # them first. The debuggers run at once, so the section takes about
    # CDB_TIMEOUT at most, however many processes there are. A window
    # destroyed since tree listed it has no owner, which
    # GetWindowThreadProcessId gives as thread and process 0; those are
    # left out.
    def self.owner_stacks(pid)
      owners = tree(pid).map { |window, _| owner(window) }
        .reject { |thread, process| thread.zero? || process.zero? || process == pid }
        .group_by(&:last).transform_values { |pairs| pairs.map(&:first).uniq.sort }
      return "owner stacks: no other process owns a window in the tree" if owners.empty?
      return "owner stacks: no debugger at #{CDB}" unless File.exist?(CDB)

      readers = owners.map do |process, threads|
        reader = Thread.new { owner_stack(process, threads) }
        reader.report_on_exception = false
        [process, reader]
      end
      sections = readers.map do |process, reader|
        reader.value
      rescue => e
        "stacks of pid #{process}: probe failed: #{e.class}: #{e.message}"
      end
      "owner stacks:\n#{sections.join("\n")}"
    end

    # The stacks of +process+, those of +threads+ first, each named in
    # the debugger's ~~[tid] form.
    #
    # These processes outlive the fixture: on Windows RealApp kills only
    # the fixture's own process, and WebView2's browser can serve the
    # next fixture with the same user data folder. So the debugger must
    # leave nothing suspended, even if capture kills it at CDB_TIMEOUT.
    # It attaches with -pvr, which Microsoft's "CDB Command-Line Options"
    # describes as "Works like -pv except that the target process is not
    # suspended", so there is nothing for a killed debugger to leave
    # suspended, and ends with qd, as stacks does, so the process keeps
    # running. The cost is that a running thread's stack may be read
    # mid-change; the threads this looks for are blocked.
    def self.owner_stack(process, threads)
      commands = threads.map { |thread| format("~~[0x%<thread>x]kn 0x%<frames>x", thread:, frames: OWNER_FRAMES) }
      command = [CDB, "-pvr", "-p", Integer(process).to_s, "-c", [*commands, "~*kn 40", "qd"].join("; ")]
      "stacks of pid #{process} (window threads #{threads.join(', ')}):\n#{capture(command, CDB_TIMEOUT)}"
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

  # Wait Chain Traversal for each thread of a process: what the kernel
  # says each one waits on, such as a SendMessage, an ALPC port, a COM
  # call, or a critical section, and which thread, in which process, that
  # waits for, followed across processes. Win32.wait_chains runs it in a
  # Ruby of its own.
  #
  # It takes the steps of Microsoft's sample "Using WCT"
  # (learn.microsoft.com/windows/win32/debug/using-wct): register COM's
  # callbacks, open a synchronous session, list the process's threads with
  # Toolhelp, enable SeDebugPrivilege, which GetThreadWaitChain's
  # reference says "The caller must have", and ask for each one's chain
  # with every out-of-process flag. As in the sample, a privilege it
  # cannot enable is reported and the walk goes on: the reference says a
  # chain then fails only if its first thread cannot be read, and
  # otherwise ends in a node whose status is NoAccess.
  #
  # Every call holds the GVL (need_gvl: true), so Fiddle reads the last
  # error straight after the call returns (fiddle 1.1.8,
  # ext/fiddle/function.c:381-394) rather than after
  # rb_thread_call_without_gvl takes the GVL back. Holding it costs
  # nothing: this runs in a Ruby of its own with one thread, which
  # capture kills if a call blocks too long.
  #
  # The signatures follow windows-sys 0.59.0
  # (Win32/System/Diagnostics/Debug/mod.rs:17, 72, 130, 145, and
  # ToolHelp/mod.rs:1, 14-15; for the privilege, Threading/mod.rs:133,
  # 244, and Security/mod.rs:55, 127), and the layouts wct.h, tlhelp32.h,
  # and winnt.h, as Microsoft documents them and windows-sys declares
  # them (Debug/mod.rs:4850-4875, ToolHelp/mod.rs:111-119,
  # Security/mod.rs:769-772, 1121-1124, Foundation/mod.rs:10248-10251).
  # real_app_test.rb checks the layout on Windows against a chain whose
  # every node it knows.
  module WaitChains
    # WCT_OBJECT_TYPE's names, from 1 (wct.h; windows-sys 0.59.0
    # Debug/mod.rs:1980-1989, 2001-2003).
    TYPES = %w[
      CriticalSection
      SendMessage
      Mutex
      Alpc
      Com
      ThreadWait
      ProcessWait
      Thread
      ComActivation
      Unknown
      SocketIo
      SmbIo
    ].freeze
    # WCT_OBJECT_STATUS's names, from 1 (wct.h; Debug/mod.rs:1990-2000).
    STATUSES = %w[NoAccess Running Blocked PidOnly PidOnlyRpcss Owned NotOwned Abandoned Unknown Error].freeze
    # WctThreadType, the one node whose union holds ThreadObject.
    THREAD = 8
    # WCT_OUT_OF_PROC_FLAG | WCT_OUT_OF_PROC_COM_FLAG |
    # WCT_OUT_OF_PROC_CS_FLAG (Debug/mod.rs:1863-1865).
    FLAGS = 0x1 | 0x2 | 0x4
    # WCT_MAX_NODE_COUNT (Debug/mod.rs:1860).
    MAX_NODES = 16
    # sizeof(WAITCHAIN_NODE_INFO). wct.h declares two WCT enums, 4 bytes
    # each, then a union of LockObject, which is WCHAR
    # ObjectName[WCT_OBJNAME_LENGTH] (128 WCHARs, 256 bytes), LARGE_INTEGER
    # Timeout (8 bytes, aligned at 8), and BOOL Alertable (4), padded to
    # 272, and ThreadObject, four DWORDs. The union starts at 8, so
    # ObjectName and ProcessId are at 8, ThreadId at 12, WaitTime at 16,
    # ContextSwitches at 20, and the whole is 280. winapi 0.3.9
    # (src/um/wct.rs) declares the union as [u64; 34], 272 bytes, to the
    # same effect.
    NODE_SIZE = 280
    # Where the union starts.
    UNION = 8
    # WCT_OBJNAME_LENGTH WCHARs, in bytes.
    NAME_SIZE = 128 * 2
    # GetThreadWaitChain's failures whose chain, its reference says, is
    # still valid.
    STILL_VALID = { 234 => "ERROR_MORE_DATA", 565 => "ERROR_TOO_MANY_THREADS" }.freeze
    # CreateToolhelp32Snapshot's flag for threads (ToolHelp/mod.rs:29).
    TH32CS_SNAPTHREAD = 0x4
    # sizeof(THREADENTRY32): seven 32-bit fields, th32ThreadID the third
    # and th32OwnerProcessID the fourth.
    THREAD_ENTRY_SIZE = 28
    INVALID_HANDLE_VALUE = -1
    # TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, as the sample opens its
    # token (Security/mod.rs:339, 351).
    TOKEN_ACCESS = 0x20 | 0x8
    # SE_DEBUG_NAME (Security/mod.rs:272).
    SE_DEBUG_NAME = "SeDebugPrivilege"
    # SE_PRIVILEGE_ENABLED (Security/mod.rs:285).
    SE_PRIVILEGE_ENABLED = 0x2
    # What AdjustTokenPrivileges leaves as the last error when it
    # succeeds without the privilege, which the token does not hold
    # (Foundation/mod.rs:3254).
    ERROR_NOT_ALL_ASSIGNED = 1300
    # sizeof(TOKEN_PRIVILEGES) with its one LUID_AND_ATTRIBUTES: the
    # 32-bit PrivilegeCount, then LUID's LowPart and HighPart, then
    # Attributes, each 32 bits, so the LUID is at 4 and Attributes at 12.
    TOKEN_PRIVILEGES_SIZE = 16

    # Writes each of +pid+'s threads' chains to +out+, one at a time.
    def self.print_report(pid, out)
      register_com(out)
      session = fn("advapi32", "OpenThreadWaitChainSession", [Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INTPTR_T).call(0, nil)
      return out.puts("OpenThreadWaitChainSession failed: error #{Fiddle.win32_last_error}") if session.zero?

      enable_debug_privilege(out)
      found = threads(pid)
      out.puts "no threads in pid #{pid}" if found.empty?
      found.each { |thread| out.puts chain(session, thread) }
    ensure
      if session&.nonzero?
        fn("advapi32", "CloseThreadWaitChainSession", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_VOID).call(session)
      end
    end

    # Lets WCT follow COM calls through ole32's own helpers, as the
    # sample does before it opens a session. Without them the chains
    # still come, only without COM's part, so a failure is only reported.
    def self.register_com(out)
      @ole32 ||= Fiddle.dlopen("ole32")
      fn("advapi32", "RegisterWaitChainCOMCallback", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
        .call(Fiddle::Pointer.new(@ole32["CoGetCallState"]), Fiddle::Pointer.new(@ole32["CoGetActivationState"]))
    rescue Fiddle::DLError => e
      out.puts "COM callbacks not registered: #{e.message}"
    end

    # Enables SeDebugPrivilege in this process's token, as the sample's
    # GrantDebugPrivilege does, or writes to +out+ why it could not.
    def self.enable_debug_privilege(out)
      process = fn("kernel32", "GetCurrentProcess", [], Fiddle::TYPE_INTPTR_T).call
      handle = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INTPTR_T, Fiddle::RUBY_FREE)
      opened = fn("advapi32", "OpenProcessToken", [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT).call(process, TOKEN_ACCESS, handle)
      return out.puts("SeDebugPrivilege not enabled: OpenProcessToken failed: error #{Fiddle.win32_last_error}") if opened.zero?

      token = handle[0, Fiddle::SIZEOF_INTPTR_T].unpack1("j")
      privileges = Fiddle::Pointer.malloc(TOKEN_PRIVILEGES_SIZE, Fiddle::RUBY_FREE)
      privileges[0, TOKEN_PRIVILEGES_SIZE] = [1, 0, 0, SE_PRIVILEGE_ENABLED].pack("L<L<l<L<")
      found = fn("advapi32", "LookupPrivilegeValueW", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT).call(nil, "#{SE_DEBUG_NAME}\0".encode(Encoding::UTF_16LE), privileges + 4)
      return out.puts("SeDebugPrivilege not enabled: LookupPrivilegeValueW failed: error #{Fiddle.win32_last_error}") if found.zero?

      adjusted = fn("advapi32", "AdjustTokenPrivileges", [
        Fiddle::TYPE_INTPTR_T,
        Fiddle::TYPE_INT,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_UINT,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_VOIDP,
      ], Fiddle::TYPE_INT).call(token, 0, privileges, TOKEN_PRIVILEGES_SIZE, nil, nil)
      error = Fiddle.win32_last_error
      if adjusted.zero?
        out.puts "SeDebugPrivilege not enabled: AdjustTokenPrivileges failed: error #{error}"
      elsif error == ERROR_NOT_ALL_ASSIGNED
        out.puts "SeDebugPrivilege not enabled: the token does not hold it"
      end
    rescue Fiddle::DLError => e
      out.puts "SeDebugPrivilege not enabled: #{e.message}"
    ensure
      fn("kernel32", "CloseHandle", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(token) if token&.nonzero?
    end

    # The ids of +pid+'s threads, from a Toolhelp snapshot.
    def self.threads(pid)
      snapshot = fn("kernel32", "CreateToolhelp32Snapshot", [Fiddle::TYPE_UINT, Fiddle::TYPE_UINT],
        Fiddle::TYPE_INTPTR_T).call(TH32CS_SNAPTHREAD, 0)
      raise "CreateToolhelp32Snapshot failed: error #{Fiddle.win32_last_error}" if snapshot == INVALID_HANDLE_VALUE

      entry = Fiddle::Pointer.malloc(THREAD_ENTRY_SIZE, Fiddle::RUBY_FREE)
      entry[0, 4] = [THREAD_ENTRY_SIZE].pack("L<")
      first, after = %w[Thread32First Thread32Next].map do |name|
        fn("kernel32", name, [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      end
      found = []
      more = first.call(snapshot, entry)
      until more.zero?
        thread, process = entry[8, 8].unpack("L<L<")
        found << thread if process == pid
        more = after.call(snapshot, entry)
      end
      found.sort
    ensure
      if snapshot && snapshot != INVALID_HANDLE_VALUE
        fn("kernel32", "CloseHandle", [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT).call(snapshot)
      end
    end

    # +thread+'s chain: a line with how many nodes it has and whether WCT
    # found a cycle, which is a deadlock, then a line for each node, the
    # first being +thread+ itself.
    def self.chain(session, thread)
      nodes = Fiddle::Pointer.malloc(NODE_SIZE * MAX_NODES, Fiddle::RUBY_FREE)
      count = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
      count[0, 4] = [MAX_NODES].pack("L<")
      cycle = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
      cycle[0, 4] = [0].pack("l<")
      succeeded = !fn("advapi32", "GetThreadWaitChain", [
        Fiddle::TYPE_INTPTR_T,
        Fiddle::TYPE_UINTPTR_T,
        Fiddle::TYPE_UINT,
        Fiddle::TYPE_UINT,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_VOIDP,
        Fiddle::TYPE_VOIDP,
      ], Fiddle::TYPE_INT).call(session, 0, FLAGS, thread, count, nodes, cycle).zero?
      error = Fiddle.win32_last_error unless succeeded
      return "thread #{thread}: GetThreadWaitChain failed: error #{error}" unless succeeded || STILL_VALID[error]

      total = count[0, 4].unpack1("L<")
      head = "thread #{thread} nodes=#{total} cycle=#{!cycle[0, 4].unpack1('l<').zero?}"
      head += " (#{STILL_VALID[error]})" if error
      lines = Array.new([total, MAX_NODES].min) { |index| "  #{node(nodes[index * NODE_SIZE, NODE_SIZE])}" }
      [head, *lines].join("\n")
    end

    # One WAITCHAIN_NODE_INFO, from its +bytes+: its type and status, and
    # for a thread its process, thread, wait time, and context switches,
    # or for an object its name, which only some objects, such as
    # mutexes, have.
    def self.node(bytes)
      type, status = bytes.unpack("l<l<")
      described = "#{label(TYPES, type, 'type')} status=#{label(STATUSES, status, 'status')}"
      if type == THREAD
        process, thread, wait, switches = bytes.unpack("@#{UNION}L<L<L<L<")
        "#{described} pid=#{process} thread=#{thread} wait_time=#{wait} context_switches=#{switches}"
      else
        object = bytes[UNION, NAME_SIZE].force_encoding(Encoding::UTF_16LE)
          .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        "#{described} name=#{object.split("\0").first.to_s.inspect}"
      end
    end

    # The name in +names+, which counts from 1, of +value+, or for a value
    # it does not hold, +kind+ and the value.
    def self.label(names, value, kind)
      (names[value - 1] if value.between?(1, names.size)) || "#{kind}#{value}"
    end

    def self.fn(library, name, args, ret)
      @libraries ||= {}
      Fiddle::Function.new((@libraries[library] ||= Fiddle.dlopen(library))[name], args, ret, need_gvl: true)
    end
  end
end
