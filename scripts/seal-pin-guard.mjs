#!/usr/bin/env node
/** Static guard for hard native-placement pins (see app/jac.toml).
 *
 * A native-pinned module may not call into a server-pinned module with a
 * non-C-ABI signature. Same-stem `.impl.jac` and `.test.jac` files are merged
 * into the native unit, so their imports count too. This source-only check
 * catches those crossings without building the native compiler kernel.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ANNEX_SUFFIXES = ['.impl.jac', '.test.jac'];
const IMPORT_FROM_RE = /^\s*import\s+from\s+([.\w]+)\s*(?:\{|\bas\b|;|$)/;
const IMPORT_PLAIN_RE = /^\s*import\s+([.\w]+)\s*(?:as\b|;|$)/;
const REPO = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

function globRe(pattern) {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*/g, '.*').replace(/\?/g, '.');
  return new RegExp(`^${escaped}$`);
}

function parsePins(tomlPath) {
  let defaultSpace = 'native';
  const pins = new Map();
  let section = '';
  const keyRe = /^\s*("[^"]+"|[A-Za-z0-9_.-]+)\s*=\s*"([^"]*)"\s*(?:#.*)?$/;
  for (const line of fs.readFileSync(tomlPath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      section = trimmed.slice(1, -1).trim();
      continue;
    }
    const match = line.match(keyRe);
    if (!match) continue;
    const key = match[1].replace(/^"|"$/g, '');
    if (section === 'placement' && key === 'default') defaultSpace = match[2];
    else if (section === 'placement.pins') pins.set(key, match[2]);
  }
  return {
    defaultSpace,
    pins,
    spaceOf(module) {
      for (const [pattern, space] of pins) if (globRe(pattern).test(module)) return space;
      return defaultSpace;
    },
    isHard(module) {
      for (const [pattern, space] of pins) if (globRe(pattern).test(module)) return space === 'native';
      return false;
    },
  };
}

function moduleName(appDir, file) {
  let rel = path.relative(appDir, file);
  const suffix = ANNEX_SUFFIXES.find((s) => rel.endsWith(s));
  rel = suffix ? rel.slice(0, -suffix.length) : rel.replace(/\.jac$/, '');
  return rel.split(path.sep).join('.');
}

function isAnnex(file) {
  return ANNEX_SUFFIXES.some((suffix) => file.endsWith(suffix));
}

function moduleFile(appDir, module) {
  const candidate = path.join(appDir, ...module.split('.')) + '.jac';
  return fs.existsSync(candidate) && fs.statSync(candidate).isFile() ? candidate : null;
}

function parseImports(file) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  const imports = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const lineno = i + 1;
    const from = line.match(IMPORT_FROM_RE);
    const plain = from ? null : line.match(IMPORT_PLAIN_RE);
    if (!from && !plain) continue;
    if (plain) {
      imports.push({ target: plain[1], names: [], lineno });
      continue;
    }
    const target = from[1];
    const names = [];
    let rest = line.slice(from.index + from[0].indexOf(target) + target.length);
    if (rest.includes('{')) {
      let chunk = rest.split('{', 2)[1];
      while (!chunk.includes('}') && i + 1 < lines.length) chunk += `\n${lines[++i]}`;
      for (const raw of chunk.split('}', 1)[0].split(',')) {
        const name = raw.trim().split(' as ')[0].trim();
        if (name) names.push(name);
      }
    }
    imports.push({ target, names, lineno });
  }
  return imports;
}

function resolveTarget(appDir, importer, target) {
  if (target.startsWith('.')) {
    const depth = target.match(/^\.+/)[0].length;
    const rest = target.slice(depth);
    let base = moduleName(appDir, importer).split('.').slice(0, -1);
    if (depth > 1) base = depth - 1 <= base.length ? base.slice(0, -(depth - 1)) : [];
    const dotted = [...base, ...rest.split('.').filter(Boolean)].join('.');
    return moduleFile(appDir, dotted) ? dotted : null;
  }
  const head = target.split('.')[0];
  return moduleFile(appDir, target) || moduleFile(appDir, head) ? target : null;
}

function calledNames(lines, names, importLine) {
  const used = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (i + 1 === importLine || line.trimStart().startsWith('#')) continue;
    for (const name of names) {
      if (!used.includes(name) && new RegExp(`\\b${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\(`).test(line)) used.push(name);
    }
  }
  return used;
}

function collect(appDir, config) {
  const findings = [];
  function visit(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!['.jac', 'node_modules', '__pycache__', '.git'].includes(entry.name)) visit(path.join(dir, entry.name));
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith('.jac')) continue;
      const file = path.join(dir, entry.name);
      const rel = path.relative(appDir, file).split(path.sep).join('/');
      if (rel.startsWith('.jac/')) continue;
      const module = moduleName(appDir, file);
      if (!config.isHard(module)) continue;
      const imports = parseImports(file);
      if (!imports.length) continue;
      const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
      for (const imp of imports) {
        const target = resolveTarget(appDir, file, imp.target);
        if (target === null || config.spaceOf(target) !== 'server') continue;
        const finding = {
          module, file: rel, target, names: imp.names,
          called: calledNames(lines, imp.names, imp.lineno), annex: isAnnex(file),
        };
        finding.key = `${finding.module} | ${finding.file} | ${finding.target}`;
        findings.push(finding);
      }
    }
  }
  visit(appDir);
  return findings;
}

function loadAllowlist(file) {
  const entries = new Map();
  if (!fs.existsSync(file)) return entries;
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const parts = line.split('|').map((part) => part.trim());
    if (parts.length >= 3) entries.set(parts.slice(0, 3).join(' | '), parts[3] ?? '');
  }
  return entries;
}

function parseArgs(argv) {
  const args = { app: path.join(REPO, 'app'), allowlist: path.join(REPO, 'scripts/seal-pin-allowlist.txt'), strict: false, writeAllowlist: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--app' && argv[i + 1]) args.app = path.resolve(argv[++i]);
    else if (arg === '--allowlist' && argv[i + 1]) args.allowlist = path.resolve(argv[++i]);
    else if (arg === '--strict') args.strict = true;
    else if (arg === '--write-allowlist') args.writeAllowlist = true;
    else if (arg === '--help' || arg === '-h') {
      console.log('Usage: node scripts/seal-pin-guard.mjs [--app app] [--allowlist PATH] [--write-allowlist] [--strict]');
      process.exit(0);
    } else throw new Error(`unknown argument: ${arg}`);
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const config = parsePins(path.join(args.app, 'jac.toml'));
  const findings = collect(args.app, config);
  let hard = findings.filter((f) => f.called.length);
  let soft = findings.filter((f) => !f.called.length);
  if (args.strict) { hard = findings; soft = []; }

  if (args.writeAllowlist) {
    const existing = loadAllowlist(args.allowlist);
    const lines = [
      '# Crossings a hard native pin may not take (see scripts/seal-pin-guard.mjs).',
      '# Format: <module> | <importing file> | <target module> | <reason>',
      '#',
      '# Every entry is a known native->server reference made from a module pinned',
      '# `"x" = "native"` in app/jac.toml (including its .impl.jac / .test.jac',
      '# annexes, which the seal folds into the module\'s native unit). A `called`',
      '# entry fails the seal with E5093 unless the signature is C-ABI only; an',
      '# imported-but-uncalled entry is a latent risk once a call site appears.',
      '#',
      '# Keep this list empty unless a crossing is genuinely unavoidable. An entry',
      '# that stops crossing is reported as XPASS — delete it then.',
      '',
    ];
    for (const f of findings.sort((a, b) => a.key.localeCompare(b.key))) {
      const reason = existing.get(f.key) || (f.called.length ? `TODO: calls ${f.called.join(',')}` : 'TODO: type/name only');
      lines.push(`${f.key} | ${reason}`);
    }
    fs.writeFileSync(args.allowlist, `${lines.join('\n')}\n`);
    console.log(`wrote ${args.allowlist} (${findings.length} crossings)`);
    return 0;
  }

  const allowed = loadAllowlist(args.allowlist);
  const unexpected = hard.filter((f) => !allowed.has(f.key));
  if (findings.length) {
    console.log(`hard native pins with server imports: ${findings.length}`);
    console.log(`  ${'state'.padEnd(9)} ${'module'.padEnd(28)} ${'file'.padEnd(34)} target`);
    for (const f of [...findings].sort((a, b) => a.key.localeCompare(b.key))) {
      const state = allowed.has(f.key) ? 'allowed' : (f.called.length ? 'CALLED' : 'imported');
      console.log(`  ${state.padEnd(9)} ${f.module.padEnd(28)} ${f.file.padEnd(34)} ${f.target}${f.called.length ? `  [${f.called.join(', ')}]` : ''}`);
    }
  }
  const keys = new Set(findings.map((f) => f.key));
  const stale = [...allowed.keys()].filter((key) => !keys.has(key)).sort();
  if (stale.length) {
    console.log();
    for (const key of stale) { console.log(`::warning::seal-pin allowlist entry no longer crosses: ${key}`); console.log(`XPASS ${key}`); }
  }
  if (unexpected.length) {
    console.log();
    for (const f of unexpected) {
      const verb = f.called.length ? `calls ${f.called.join(', ')} in` : 'imports';
      console.log(`::error file=app/${f.file}::hard native pin '${f.module}' ${verb} '${f.target}' from ${f.file}; the seal will fail with E5093 unless that signature is C-ABI only. Move the case to a server-placed suite, or add a reviewed allowlist entry.`);
    }
    console.log();
    console.log(`FAIL: ${unexpected.length} unlisted native->server call(s) under a hard pin.`);
    return 1;
  }
  void soft;
  console.log();
  console.log('OK: no unlisted native->server calls under a hard native pin.');
  return 0;
}

try { process.exitCode = main(); }
catch (err) { console.error(`seal-pin-guard: ${err.message}`); process.exitCode = 2; }
