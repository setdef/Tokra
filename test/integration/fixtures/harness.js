// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The page half of test/integration/support/fixture_app.rb. A fixture page
// runs named checks with check(), then calls finish(). finish() reports the
// results over a plain Rack POST (so a broken IPC layer still reports) and,
// unless the app was started with --wait, asks Ruby to exit through
// plugin:fixture|exit.
(function () {
  const results = [];

  // A check that never settles fails instead of hanging the run; the test's
  // own timeout bounds the whole app.
  function withTimeout(promise, ms, what) {
    return Promise.race([
      promise,
      new Promise((_, reject) => setTimeout(() => reject(new Error(`${what} timed out`)), ms)),
    ]);
  }

  async function check(name, run) {
    const item = document.createElement('li');
    item.textContent = name;
    document.getElementById('checks').append(item);
    let result;
    try {
      const { pass, detail } = await withTimeout(run(), 20000, name);
      result = { name, pass: !!pass, detail };
    } catch (error) {
      result = { name, pass: false, detail: { error: String(error) } };
    }
    results.push(result);
    item.textContent = `${result.pass ? 'PASS' : 'FAIL'} ${name}: ${JSON.stringify(result.detail)}`;
    return result;
  }

  async function finish() {
    const passed = results.every((r) => r.pass);
    await fetch('/report', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ passed, checks: results }),
    });
    const options = await (await fetch('/options.json')).json();
    if (options.wait) return;
    window.__TAURI_INTERNALS__.invoke('plugin:fixture|exit', { code: passed ? options.exitCode : 1 });
  }

  window.fixture = { check, finish, withTimeout };
})();
