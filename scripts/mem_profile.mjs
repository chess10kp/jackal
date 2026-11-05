#!/usr/bin/env node
/** Sample RSS across a command's process tree without a Python host. */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function parseArgs(argv) {
  const args = { idleSeconds: 8, timeout: 600, cmd: [] };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--') { args.cmd = argv.slice(i + 1); break; }
    if (argv[i] === '--idle-seconds' && argv[i + 1]) args.idleSeconds = Number(argv[++i]);
    else if (argv[i] === '--timeout' && argv[i + 1]) args.timeout = Number(argv[++i]);
    else if (argv[i] === '-h' || argv[i] === '--help') {
      console.log('Usage: node scripts/mem_profile.mjs [--idle-seconds N] [--timeout N] -- CMD...');
      process.exit(0);
    } else if (args.cmd.length === 0) args.cmd = argv.slice(i);
  }
  if (!args.cmd.length) throw new Error('a command is required after --');
  return args;
}

function darwinParents() {
  const result = spawnSync('ps', ['-A', '-o', 'pid=,ppid=', '-ww'], { encoding: 'utf8', timeout: 5000 });
  const parents = new Map();
  if (result.status !== 0) return parents;
  for (const line of result.stdout.split(/\r?\n/)) {
    const parts = line.trim().split(/\s+/);
    if (parts.length === 2 && /^\d+$/.test(parts[0]) && /^\d+$/.test(parts[1])) parents.set(Number(parts[0]), Number(parts[1]));
  }
  return parents;
}

function linuxParents() {
  const parents = new Map();
  let entries;
  try { entries = fs.readdirSync('/proc'); } catch { return parents; }
  for (const entry of entries) {
    if (!/^\d+$/.test(entry)) continue;
    try {
      const stat = fs.readFileSync(`/proc/${entry}/stat`, 'utf8').split(') ').at(-1).split(' ');
      parents.set(Number(entry), Number(stat[1]));
    } catch { /* raced process exit or permission change */ }
  }
  return parents;
}

function treePids(root) {
  const parents = os.platform() === 'darwin' ? darwinParents() : linuxParents();
  const found = [];
  for (const pid of parents.keys()) {
    let cur = pid;
    for (let hops = 0; hops < 64 && parents.has(cur) && cur !== 1; hops += 1) {
      if (cur === root) { found.push(pid); break; }
      cur = parents.get(cur);
    }
  }
  return found;
}

function rssKb(pid) {
  if (os.platform() === 'darwin') {
    const result = spawnSync('ps', ['-p', String(pid), '-o', 'rss='], { encoding: 'utf8', timeout: 5000 });
    const value = Number(result.stdout.trim().split(/\s+/)[0]);
    return result.status === 0 && Number.isFinite(value) ? value : null;
  }
  try {
    const line = fs.readFileSync(`/proc/${pid}/status`, 'utf8').split(/\r?\n/).find((row) => row.startsWith('VmRSS:'));
    return line ? Number(line.trim().split(/\s+/)[1]) : null;
  } catch { return null; }
}

function processName(pid) {
  if (os.platform() === 'darwin') {
    const result = spawnSync('ps', ['-p', String(pid), '-o', 'comm='], { encoding: 'utf8', timeout: 5000 });
    return result.status === 0 ? path.basename(result.stdout.trim()) : '?';
  }
  try { return path.basename(fs.readlinkSync(`/proc/${pid}/exe`)); }
  catch { return '?'; }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const child = spawn(args.cmd[0], args.cmd.slice(1), { stdio: ['pipe', 'pipe', 'pipe'] });
  if (!child.pid) throw new Error(`could not start ${args.cmd[0]}`);
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdin.on('error', () => {});
  for (const stream of [child.stdout, child.stderr]) {
    let pending = '';
    stream.on('data', (chunk) => {
      pending += chunk;
      const lines = pending.split(/\r?\n/);
      pending = lines.pop() ?? '';
      for (const line of lines) process.stderr.write(`app| ${line}\n`);
    });
    stream.on('end', () => { if (pending) process.stderr.write(`app| ${pending}\n`); });
  }
  child.stdin.write('say hi\n');
  const exitPromise = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => resolve({ code: code ?? (signal ? 128 : 1), signal }));
  });
  const exitInput = setTimeout(() => { child.stdin.write('/exit\n'); child.stdin.end(); }, args.idleSeconds * 1000);
  const start = Date.now();
  let peak = 0;
  let last = 0;
  let samples = 0;
  const peaks = new Map();
  const names = new Map();
  let exited = false;
  let exitInfo;
  exitPromise.then((value) => { exited = true; exitInfo = value; }).catch(() => { exited = true; });
  while (!exited && Date.now() - start < args.timeout * 1000) {
    let total = 0;
    for (const pid of treePids(child.pid)) {
      const rss = rssKb(pid);
      if (rss === null) continue;
      total += rss;
      if (!peaks.has(pid) || rss > peaks.get(pid)) {
        peaks.set(pid, rss);
        names.set(pid, processName(pid));
      }
    }
    if (total) { peak = Math.max(peak, total); last = total; samples += 1; }
    await sleep(200);
  }
  if (!exited) { child.kill('SIGKILL'); exitInfo = await exitPromise; }
  else { exitInfo = await exitPromise; }
  clearTimeout(exitInput);
  const worstPid = [...peaks.keys()].sort((a, b) => peaks.get(b) - peaks.get(a))[0];
  console.log(JSON.stringify({
    cmd: args.cmd.join(' '), returncode: exitInfo.code, samples,
    tree_peak_kb: peak, idle_kb: last,
    worst_process: worstPid === undefined ? null : { pid: worstPid, kb: peaks.get(worstPid), exe: names.get(worstPid) ?? '?' },
    per_process_peak_kb: Object.fromEntries([...peaks].map(([pid, kb]) => [String(pid), { kb, exe: names.get(pid) ?? '?' }])),
  }));
}

main().catch((err) => { console.error(`mem_profile: ${err.message}`); process.exitCode = 2; });
