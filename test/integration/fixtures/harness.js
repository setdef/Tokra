// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The page half of test/integration/support/fixture_app.rb. A fixture page
// runs named checks with check(), then calls finish(). finish() reports the
// results over a plain Rack POST (so a broken IPC layer still reports) and,
// unless the app was started with --wait, asks Ruby to exit through
// plugin:fixture|exit, or through the command finish({ exitCommand }) names.
//
// Each check posts its start and its end to /progress, which Ruby prints
// as PROGRESS lines: RealApp counts a fixture hung only once it prints
// nothing for its stall bound, so these lines are what let a slow page
// keep going on a busy machine (Plan 060).
(function () {
  const results = [];

  // The run's options: the exit code, --wait, and patience, the
  // milliseconds a wait may last (FixtureApp::PATIENCE), which RealApp's
  // stall bound outlasts by a margin, so a check that times out is
  // reported before RealApp would kill the app for its silence.
  const options = fetch('/options.json').then((response) => response.json());

  // The first check that timed out, once one has. A page whose check
  // hangs is likely to hang in the next, so the checks after it fail at
  // once, naming it, rather than each waiting out its patience too.
  let timedOut = null;

  // A wait that never settles fails instead of hanging the run. It is
  // bounded by the run's patience, not by a guess at how long a healthy
  // page takes: a loaded machine can make a page many times slower, and a
  // shorter bound would fail a run RealApp lets pass.
  async function withTimeout(promise, what) {
    const { patience } = await options;
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        const error = new Error(`${what} timed out after ${patience} ms`);
        error.timedOut = true;
        reject(error);
      }, patience);
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
  }

  // Tells Ruby check +name+ reached +stage+ ('start' or 'end'). A post
  // that fails does not fail the check: the report still goes out, and
  // RealApp sees the silence.
  async function progress(stage, name) {
    try {
      await fetch('/progress', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ stage, name }),
      });
    } catch (_error) {
      // Reported by the missing PROGRESS line.
    }
  }

  // Runs check +name+, unless an earlier check timed out, which fails it
  // unrun. +run+ gets an AbortSignal that aborts once the check is
  // reported, so work a timed-out check left running can stop before it
  // acts on the next check's state.
  async function check(name, run) {
    const item = document.createElement('li');
    item.textContent = name;
    document.getElementById('checks').append(item);
    await progress('start', name);
    const reported = new AbortController();
    let result;
    if (timedOut) {
      result = { name, pass: false, detail: { error: `not run: ${timedOut} timed out first` } };
    } else {
      try {
        const { pass, detail } = await withTimeout(run(reported.signal), name);
        result = { name, pass: !!pass, detail };
      } catch (error) {
        if (error && error.timedOut) timedOut = name;
        result = { name, pass: false, detail: { error: String(error) } };
      } finally {
        reported.abort();
      }
    }
    results.push(result);
    item.textContent = `${result.pass ? 'PASS' : 'FAIL'} ${name}: ${JSON.stringify(result.detail)}`;
    await progress('end', name);
    return result;
  }

  async function finish({ exitCommand = 'plugin:fixture|exit' } = {}) {
    const passed = results.every((r) => r.pass);
    await fetch('/report', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ passed, checks: results }),
    });
    const { wait, exitCode } = await options;
    if (wait) return;
    window.__TAURI_INTERNALS__.invoke(exitCommand, { code: passed ? exitCode : 1 });
  }

  window.fixture = { check, finish, withTimeout };
})();
