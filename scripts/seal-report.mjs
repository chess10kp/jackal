#!/usr/bin/env node
/** Summarize a `jac build` log into the seal-wall table. */
import fs from 'node:fs';
import readline from 'node:readline';

const RE_UNIT = /\[\s*(\d+)\/\d+\]\s+(\S+\.jac)/;
const RE_HARD = /FAIL \(native unit did not lower\):\s*(\S+\.jac)/;
const RE_SOFT = /note:\s*(\S+\.jac)\s+preferred native but did not lower; compiled in the server codespace \(error\[(E\d+)\]:\s*([^)]*)\)/;
const RE_DEMOTE = /native seam -- demoting (\S+) to Python-only \(un-lowerable\):\s*(.*)/;
const RE_ERASE = /native seam -- erasing field (\S+)\.(\S+) to an opaque slot \(un-lowerable declaration\):\s*(.*)/;
const RE_ABORT = /Error: Seal aborted:\s*(.*)/;
const RE_ERR = /error\[(E\d+)\]:\s*(.*)/;
const RE_SEAL_FAILED = /Error: Seal failed/;
const RE_CAUSE_FILE = /([\w./-]+\.jac), line (\d+), col (\d+): (.*)/;

function causeKey(diag) {
  const match = diag.match(RE_CAUSE_FILE);
  return match ? [match[1].split('/').at(-1), match[4].trim()] : ['<unlocated>', diag.trim().slice(0, 120)];
}

function increment(map, key, amount = 1) { map.set(key, (map.get(key) ?? 0) + amount); }
function topEntries(map) { return [...map].sort((a, b) => b[1] - a[1]); }

function summarize(lines) {
  let unit = '';
  const failures = new Map();
  const soft = new Map();
  const erased = new Map();
  const demotions = new Map();
  const causeFiles = new Map();
  const causeExamples = new Map();
  const firstCause = new Map();
  const codes = new Map();
  let abort = '';
  let sealFailed = false;
  for (const raw of lines) {
    const line = raw.replace(/[\r\n]+$/, '');
    let match = line.match(RE_UNIT);
    if (match) unit = match[2];
    match = line.match(RE_HARD);
    if (match) { if (!failures.has(match[1])) failures.set(match[1], 0); continue; }
    match = line.match(RE_SOFT);
    if (match) { soft.set(match[1], `${match[2]}: ${match[3].trim()}`); continue; }
    match = line.match(RE_ERASE);
    if (match) {
      const key = `${match[1]}.${match[2]}`;
      const why = match[3].split(';', 1)[0].trim();
      if (!erased.has(key)) erased.set(key, []);
      if (why && !erased.get(key).includes(why)) erased.get(key).push(why);
      continue;
    }
    match = line.match(RE_DEMOTE);
    if (match) {
      increment(demotions, unit);
      if (failures.has(unit)) increment(failures, unit);
      for (const diag of match[2].split(/;\s*(?=\/|[A-Za-z_][\w./-]*\.jac, line)/)) {
        const [file, message] = causeKey(diag);
        increment(causeFiles, file);
        const key = `${file}: ${message}`;
        if (!causeExamples.has(key)) causeExamples.set(key, diag.trim().slice(0, 200));
        if (failures.has(unit) && !firstCause.has(unit)) firstCause.set(unit, key);
      }
      continue;
    }
    match = line.match(RE_ABORT);
    if (match) { abort = match[1].trim(); continue; }
    match = line.match(RE_ERR);
    if (match && !codes.has(match[1])) codes.set(match[1], match[2].trim());
    if (RE_SEAL_FAILED.test(line)) sealFailed = true;
  }
  const softModules = new Map([...soft].map(([file, why]) => [file.split('/').at(-1), why]));
  return {
    hard_units: Object.fromEntries(failures),
    hard_units_first_cause: Object.fromEntries(firstCause),
    soft_modules: Object.fromEntries(softModules),
    erased_fields: Object.fromEntries(erased),
    demotions_by_unit: Object.fromEntries(topEntries(demotions)),
    cause_files: Object.fromEntries(topEntries(causeFiles)),
    cause_examples: Object.fromEntries([...causeExamples].slice(0, 12)),
    abort: abort.slice(0, 600),
    codes: Object.fromEntries(codes),
    seal_failed: sealFailed,
  };
}

function printReport(data) {
  const hard = Object.entries(data.hard_units);
  const erased = Object.entries(data.erased_fields);
  const soft = Object.entries(data.soft_modules);
  console.log('='.repeat(78));
  console.log('HARD WALLS (the seal cannot complete)');
  console.log('='.repeat(78));
  if (hard.length) {
    for (const [unit, count] of hard) {
      console.log(`  ${unit}  (${count} demoted element(s) in this unit)`);
      if (data.hard_units_first_cause[unit]) console.log(`      first: ${data.hard_units_first_cause[unit]}`);
    }
  } else console.log('  (none recorded)');
  const causes = Object.entries(data.cause_files).slice(0, 8);
  if (causes.length) {
    console.log('\nROOT CAUSES (source files the demotion diagnostics point at)');
    for (const [file, count] of causes) {
      console.log(`  ${String(count).padStart(4)}  ${file}`);
      for (const [key, example] of Object.entries(data.cause_examples).filter(([key]) => key.startsWith(`${file}: `)).slice(0, 2)) {
        void key; console.log(`          ${example}`);
      }
    }
  }
  if (erased.length) {
    console.log('\nERASED FIELDS (a field type that would not lower)');
    for (const [field, reasons] of erased) {
      console.log(`  ${field}`);
      for (const why of reasons.slice(0, 3)) console.log(`          ${why.replace(/\/tmp\/[^/]+\/jackal\//g, '')}`);
    }
  }
  if (soft.length) {
    console.log('\nSOFT MODULE DEMOTIONS (allowed; each is distance from N6)');
    for (const [module, why] of soft) console.log(`  ${module}: ${why}`);
  }
  console.log('\n' + '='.repeat(78));
  if (data.abort) console.log(`SEAL ABORT: ${data.abort.replace(/\/tmp\/[^/]+\/jackal\//g, '').slice(0, 400)}`);
  for (const [code, message] of Object.entries(data.codes)) console.log(`  ${code}: ${message.slice(0, 200)}`);
  if (!data.abort && !data.seal_failed) console.log('(no seal abort found — build may have succeeded or the log is partial)');
  console.log('='.repeat(78));
}

async function main(argv) {
  let json = false;
  let logFile = '';
  for (const arg of argv) {
    if (arg === '--json') json = true;
    else if (arg === '--help' || arg === '-h') {
      console.log('Usage: node scripts/seal-report.mjs [--json] [BUILD_LOG]');
      return 0;
    } else if (!logFile) logFile = arg;
    else throw new Error(`unexpected argument: ${arg}`);
  }
  let lines;
  if (logFile) lines = fs.readFileSync(logFile, 'utf8').split(/\r?\n/);
  else {
    const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
    lines = [];
    for await (const line of input) lines.push(line);
  }
  const data = summarize(lines);
  if (json) console.log(JSON.stringify(data, null, 2));
  else printReport(data);
  return 0;
}

main(process.argv.slice(2)).then((code) => { process.exitCode = code; })
  .catch((err) => { console.error(`seal-report: ${err.message}`); process.exitCode = 2; });
