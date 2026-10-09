#!/usr/bin/env node
// tokenbar install | uninstall (TRD Section 13). Node built-in modules only.
'use strict';
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const DOMAIN = 'com.patronofalltrades.TokenBar';

const defaults = {
  home: os.homedir(),
  arch: process.arch,
  darwinMajor: parseInt(os.release(), 10), // Darwin 23 = macOS 14.
  zip: path.join(__dirname, '..', 'TokenBar.zip'),
  run: (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }),
  log: console.log,
};

function quit(o) {
  try { o.run('/usr/bin/pkill', ['-x', 'TokenBar']); } catch { /* exit 1: TokenBar does not run */ }
}

function install(o) {
  if (o.arch !== 'arm64') throw new Error('TokenBar needs a Mac with Apple silicon (arm64). Intel Macs are not supported.');
  if (!(o.darwinMajor >= 23)) throw new Error('TokenBar needs macOS 14 (Sonoma) or later.');
  if (!fs.existsSync(o.zip)) throw new Error(`TokenBar.zip is missing from the package: ${o.zip}`);

  const appDir = path.join(o.home, 'Applications');
  const dest = path.join(appDir, 'TokenBar.app');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tokenbar-'));
  try {
    quit(o);
    o.run('/usr/bin/ditto', ['-x', '-k', o.zip, tmp]);
    const app = path.join(tmp, 'TokenBar.app');
    try {
      o.run('/usr/bin/codesign', ['--verify', '--strict', app]);
    } catch (e) {
      throw new Error(`The TokenBar.app signature is not valid. Nothing was installed.\n${e.stderr || e.message}`);
    }
    fs.mkdirSync(appDir, { recursive: true });
    fs.rmSync(dest, { recursive: true, force: true });
    o.run('/usr/bin/ditto', [app, dest]); // ditto keeps modes, links and signature files on any volume.
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  o.log(`Installed ${dest}`);

  let quarantined = true;
  try { o.run('/usr/bin/xattr', ['-p', 'com.apple.quarantine', dest]); } catch { quarantined = false; }
  if (quarantined) {
    o.log([
      'macOS marked TokenBar.app as downloaded (com.apple.quarantine), so the first launch can be blocked.',
      'If macOS blocks TokenBar:',
      '  1. Open System Settings > Privacy & Security.',
      '  2. Scroll to Security. Click "Open Anyway" next to the TokenBar message.',
      '  3. Enter your password and click "Open".',
    ].join('\n'));
  }
  o.run('/usr/bin/open', [dest]);
}

// Undo Claude Connect, as Disconnect in Settings does (IES-223). Without it, Claude Code runs a deleted app.
// Puts back the saved status line, or removes the key. Changes nothing if the status line is not TokenBar's.
function disconnectClaude(o) {
  let file = path.join(o.home, '.claude', 'settings.json');
  if (!fs.existsSync(file)) return;
  file = fs.realpathSync(file); // keep a dotfiles link
  let settings;
  try { settings = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { settings = null; }
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) {
    o.log(`Did not change ${file}: it is not a valid JSON object.`);
    return;
  }
  const command = settings.statusLine && settings.statusLine.command;
  if (typeof command !== 'string' || !command.includes('--statusline') || !command.includes('TokenBar')) return;
  const previousFile = path.join(o.home, 'Library', 'Application Support', 'TokenBar', 'statusline-previous.json');
  let previous;
  try { previous = JSON.parse(fs.readFileSync(previousFile, 'utf8')); } catch { previous = undefined; }
  fs.copyFileSync(file, `${file}.tokenbar-uninstall-backup`);
  if (previous === undefined) delete settings.statusLine; else settings.statusLine = previous;
  fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
  fs.rmSync(previousFile, { force: true });
  o.log(previous === undefined
    ? `Removed the TokenBar status line from ${file}.`
    : `Restored your previous Claude Code status line in ${file}.`);
}

function uninstall(o) {
  quit(o);
  const dest = path.join(o.home, 'Applications', 'TokenBar.app');
  fs.rmSync(dest, { recursive: true, force: true });
  o.log(`Removed ${dest}`);
  disconnectClaude(o);
  o.log(`Settings stay in the UserDefaults domain ${DOMAIN}`);
  o.log(`(${path.join(o.home, 'Library', 'Preferences', DOMAIN + '.plist')}).`);
  o.log(`To remove them, run: defaults delete ${DOMAIN}`);
}

function main(argv, opts = {}) {
  const o = { ...defaults, ...opts };
  const cmds = { install, uninstall };
  const cmd = Object.hasOwn(cmds, argv[0]) && cmds[argv[0]];
  if (!cmd) {
    o.log('Usage: tokenbar install | tokenbar uninstall');
    return argv[0] ? 1 : 0;
  }
  cmd(o);
  return 0;
}

module.exports = { main };

if (require.main === module) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (e) {
    console.error(`tokenbar: ${e.message}`);
    process.exitCode = 1;
  }
}
