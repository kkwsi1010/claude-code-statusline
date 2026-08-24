#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ===================================================
// Environment detection
// ===================================================
const isWSLFS = fs.existsSync('/proc/version');
let isWSLRuntime = false;
try {
  if (isWSLFS) {
    isWSLRuntime = fs.readFileSync('/proc/version', 'utf8').toLowerCase().includes('microsoft');
  }
} catch (e) {}

// ===================================================
// Collect install targets (install to all detected paths)
// ===================================================
const targets = [];

function addTarget(home, shellType) {
  if (!home || !fs.existsSync(home)) return;
  targets.push({
    home,
    claudeDir: path.join(home, '.claude'),
    scriptDest: path.join(home, '.claude', 'statusline.sh'),
    scriptPsDest: path.join(home, '.claude', 'statusline.ps1'),
    helperPsDest: path.join(home, '.claude', 'devlauncher-cache-refresh.ps1'),
    confDest: path.join(home, '.claude', 'statusline.conf'),
    settingsPath: path.join(home, '.claude', 'settings.json'),
    shellType
  });
}

if (isWSLRuntime) {
  // WSL native - install to WSL home only
  addTarget(process.env.HOME || `/home/${process.env.USER || require('os').userInfo().username}`, 'bash');
} else if (process.platform === 'win32') {
  // Windows - always install to Windows home
  addTarget(process.env.USERPROFILE, 'powershell');

  // Also install to WSL home if WSL is available
  try {
    const wslUser = execSync('wsl.exe -e whoami', { encoding: 'utf8', timeout: 3000 }).trim();
    if (wslUser) {
      for (const distro of ['Ubuntu', 'Ubuntu-24.04', 'Ubuntu-22.04', 'Ubuntu-20.04', 'Debian']) {
        const wslHome = `\\\\wsl.localhost\\${distro}\\home\\${wslUser}`;
        if (fs.existsSync(wslHome)) {
          addTarget(wslHome, 'bash');
          break;
        }
      }
    }
  } catch (e) {}
} else {
  addTarget(process.env.HOME, 'bash');
}

if (targets.length === 0) {
  console.error('ERROR: Could not determine installation path.');
  process.exit(1);
}

const scriptSrc = path.join(__dirname, 'statusline.sh');
const scriptPsSrc = path.join(__dirname, 'statusline.ps1');
const helperPsSrc = path.join(__dirname, 'devlauncher-cache-refresh.ps1');
const confSrc = path.join(__dirname, 'statusline.conf.example');

// Backward compat for uninstall
const primary = targets[0];
const { claudeDir, scriptDest, scriptPsDest, confDest, settingsPath } = primary;

const cmd = process.argv[2];

// ===================================================
// Install to a single target
// ===================================================
function installTo(t) {
  console.log(`\n[${t.shellType === 'bash' ? 'WSL/Linux' : 'Windows'}] Installing to ${t.home}`);
  if (!fs.existsSync(t.claudeDir)) fs.mkdirSync(t.claudeDir, { recursive: true });

  // Copy scripts
  fs.copyFileSync(scriptSrc, t.scriptDest);
  try { fs.chmodSync(t.scriptDest, 0o755); } catch (e) {}
  const ps1Content = fs.readFileSync(scriptPsSrc);
  const bom = Buffer.from([0xEF, 0xBB, 0xBF]);
  fs.writeFileSync(t.scriptPsDest, Buffer.concat([bom, ps1Content]));
  console.log(`  statusline.sh -> ${t.scriptDest}`);
  console.log(`  statusline.ps1 -> ${t.scriptPsDest}`);

  if (t.shellType === 'powershell' && fs.existsSync(helperPsSrc)) {
    fs.copyFileSync(helperPsSrc, t.helperPsDest);
    console.log(`  devlauncher-cache-refresh.ps1 -> ${t.helperPsDest}`);
  }

  if (!fs.existsSync(t.confDest)) {
    // Write conf with UTF-8 BOM so PowerShell reads unicode correctly
    const confContent = fs.readFileSync(confSrc);
    fs.writeFileSync(t.confDest, Buffer.concat([bom, confContent]));
    console.log(`  statusline.conf -> ${t.confDest}`);
  }

  // Update settings.json
  let settings = {};
  if (fs.existsSync(t.settingsPath)) {
    try { settings = JSON.parse(fs.readFileSync(t.settingsPath, 'utf8')); } catch (e) {}
  }

  const shellArg = process.argv.indexOf('--shell') >= 0 ? process.argv[process.argv.indexOf('--shell') + 1] : null;
  const actualShell = shellArg || t.shellType;

  let shellCmd;
  if (actualShell === 'bash') {
    shellCmd = `bash ~/.claude/statusline.sh`;
  } else {
    // Use Windows-style path for PowerShell
    const winPath = t.scriptPsDest.replace(/\\/g, '\\\\');
    shellCmd = `powershell -NoProfile -ExecutionPolicy Bypass -File "${winPath}"`;
  }

  // Polling: refreshInterval re-runs the command on a fixed timer so the bar
  // also updates during idle periods (after /compact, before first message, etc.)
  const POLL_SECONDS = 2;
  const existingCmd = settings.statusLine && settings.statusLine.command;
  if (existingCmd && (existingCmd.includes('statusline.sh') || existingCmd.includes('statusline.ps1')) && !shellArg) {
    // Keep existing command, but ensure polling is on (older installs may lack it or have a long interval)
    const cur = settings.statusLine.refreshInterval;
    if (!cur || cur > 3) settings.statusLine.refreshInterval = POLL_SECONDS;
    console.log(`  settings.json: keeping "${existingCmd}" (refreshInterval=${settings.statusLine.refreshInterval}s)`);
  } else {
    settings.statusLine = { type: 'command', command: shellCmd, refreshInterval: POLL_SECONDS };
    console.log(`  settings.json: command = "${shellCmd}" (refreshInterval=${POLL_SECONDS}s)`);
  }

  fs.writeFileSync(t.settingsPath, JSON.stringify(settings, null, 2) + '\n');
}

function install() {
  for (const t of targets) installTo(t);
  console.log('\nDone! Restart Claude Code to see the status line.');
  console.log('Edit statusline.conf in your .claude dir to customize.');
}

function uninstall() {
  for (const t of targets) {
    if (fs.existsSync(t.scriptDest)) fs.unlinkSync(t.scriptDest);
    if (fs.existsSync(t.scriptPsDest)) fs.unlinkSync(t.scriptPsDest);
    if (fs.existsSync(t.helperPsDest)) fs.unlinkSync(t.helperPsDest);
    if (fs.existsSync(t.settingsPath)) {
      try {
        const s = JSON.parse(fs.readFileSync(t.settingsPath, 'utf8'));
        delete s.statusLine;
        fs.writeFileSync(t.settingsPath, JSON.stringify(s, null, 2) + '\n');
        console.log(`Removed statusLine from ${t.settingsPath}`);
      } catch (e) {}
    }
  }
  console.log('Uninstalled. Restart Claude Code to apply.');
}

function showHelp() {
  console.log(`cc-statusbar - Status line for Claude Code

Usage:
  npx cc-statusbar               Open settings TUI
  npx cc-statusbar install       Install (auto-detects WSL + Windows)
  npx cc-statusbar uninstall     Remove
  npx cc-statusbar update        Reinstall from latest
  npx cc-statusbar help          This help

Flags:
  --shell bash         Force bash command
  --shell powershell   Force powershell command

Repo: https://github.com/DreamingStrawberry/claude-code-statusline`);
}

switch (cmd) {
  case 'install': install(); break;
  case 'uninstall': case 'remove': uninstall(); break;
  case 'update': install(); break;
  case 'help': case '--help': case '-h': showHelp(); break;
  default: console.log(`Unknown command: ${cmd}. Use 'help' for usage.`); process.exit(1);
}
