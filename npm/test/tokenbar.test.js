'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { main } = require('../bin/tokenbar.js');

const homes = [];
test.after(() => homes.forEach((h) => fs.rmSync(h, { recursive: true, force: true })));

// A fake runner: records each call and makes `ditto -x -k` write a fake app. No real command runs.
function setup({ signatureOK = true, quarantine = false, arch = 'arm64', darwinMajor = 23 } = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'tokenbar-home-'));
  homes.push(home);
  const zip = path.join(home, 'TokenBar.zip');
  fs.writeFileSync(zip, '');
  const calls = [];
  const lines = [];
  const fail = () => { throw Object.assign(new Error('exit 1'), { stderr: 'invalid signature' }); };
  const run = (cmd, args) => {
    calls.push([path.basename(cmd), ...args]);
    if (cmd.endsWith('ditto') && args[0] === '-x') {
      fs.mkdirSync(path.join(args[3], 'TokenBar.app', 'Contents'), { recursive: true });
      fs.writeFileSync(path.join(args[3], 'TokenBar.app', 'Contents', 'Info.plist'), 'new');
    } else if (cmd.endsWith('ditto')) {
      fs.cpSync(args[0], args[1], { recursive: true });
    } else if (cmd.endsWith('codesign') && !signatureOK) fail();
    else if (cmd.endsWith('xattr') && !quarantine) fail();
    else if (cmd.endsWith('pkill')) fail(); // TokenBar does not run.
    return '';
  };
  const opts = { home, zip, run, arch, darwinMajor, log: (s) => lines.push(s) };
  const app = path.join(home, 'Applications', 'TokenBar.app');
  return { home, app, calls, opts, out: () => lines.join('\n') };
}

test('install replaces the app, verifies the signature and opens the app', () => {
  const t = setup();
  fs.mkdirSync(path.join(t.app, 'Contents'), { recursive: true });
  fs.writeFileSync(path.join(t.app, 'old-file'), 'old');

  assert.strictEqual(main(['install'], t.opts), 0);
  assert.strictEqual(fs.readFileSync(path.join(t.app, 'Contents', 'Info.plist'), 'utf8'), 'new');
  assert.ok(!fs.existsSync(path.join(t.app, 'old-file')));
  const names = t.calls.map((c) => c[0]);
  assert.deepStrictEqual(names, ['pkill', 'ditto', 'codesign', 'ditto', 'xattr', 'open']);
  assert.deepStrictEqual(t.calls[1].slice(0, 3), ['ditto', '-x', '-k']);
  assert.deepStrictEqual(t.calls[2].slice(1, 3), ['--verify', '--strict']);
  assert.deepStrictEqual(t.calls.at(-1), ['open', t.app]);
  assert.doesNotMatch(t.out(), /Open Anyway/);
});

test('install creates ~/Applications when it does not exist', () => {
  const t = setup();
  assert.ok(!fs.existsSync(path.join(t.home, 'Applications')));
  main(['install'], t.opts);
  assert.ok(fs.existsSync(t.app));
});

test('install stops when the signature check fails and keeps the old app', () => {
  const t = setup({ signatureOK: false });
  fs.mkdirSync(t.app, { recursive: true });
  fs.writeFileSync(path.join(t.app, 'old-file'), 'old');
  assert.throws(() => main(['install'], t.opts), /signature is not valid/);
  assert.ok(fs.existsSync(path.join(t.app, 'old-file')));
  assert.ok(!t.calls.some((c) => c[0] === 'open'));
});

test('install shows the Open Anyway steps when the app has com.apple.quarantine', () => {
  const t = setup({ quarantine: true });
  main(['install'], t.opts);
  assert.match(t.out(), /Open Anyway/);
  assert.ok(!t.calls.some((c) => c.includes('-d') || c.includes('-r')), 'must not remove the attribute');
});

test('install stops on Intel and below macOS 14 before it changes anything', () => {
  for (const [opt, re] of [[{ arch: 'x64' }, /Apple silicon/], [{ darwinMajor: 22 }, /macOS 14/]]) {
    const t = setup(opt);
    assert.throws(() => main(['install'], t.opts), re);
    assert.deepStrictEqual(t.calls, []);
  }
});

test('uninstall removes the app and keeps settings', () => {
  const t = setup();
  fs.mkdirSync(t.app, { recursive: true });
  const prefs = path.join(t.home, 'Library', 'Preferences', 'com.patronofalltrades.TokenBar.plist');
  fs.mkdirSync(path.dirname(prefs), { recursive: true });
  fs.writeFileSync(prefs, 'settings');

  assert.strictEqual(main(['uninstall'], t.opts), 0);
  assert.ok(!fs.existsSync(t.app));
  assert.ok(fs.existsSync(prefs));
  assert.deepStrictEqual(t.calls.map((c) => c[0]), ['pkill']);
  assert.match(t.out(), /com\.patronofalltrades\.TokenBar/);
});

test('an unknown command prints usage and returns 1', () => {
  const t = setup();
  assert.strictEqual(main(['nope'], t.opts), 1);
  assert.match(t.out(), /Usage/);
});
