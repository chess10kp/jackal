#!/usr/bin/env node
/** Convert TypeScript source trees to Jac floors through the js2jac Bun bridge. */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith('--') || !argv[i + 1]) throw new Error(`expected --name value, got ${key}`);
    out[key.slice(2)] = argv[++i];
  }
  for (const key of ['out', 'driver', 'summary', 'project-log', 'jac-cwd']) {
    if (!out[key]) throw new Error(`missing --${key}`);
  }
  if (!out['source-root'] && !out['package-root']) throw new Error('missing --source-root or --package-root');
  if (!out.base && !out['package-root']) throw new Error('missing --base');
  return out;
}

function snakeSegment(segment) {
  if (segment === '.' || segment === '..') return segment;
  let output = segment.replace(/[^A-Za-z0-9_]+/g, '_');
  if (/^[0-9]/.test(output)) output = `_${output}`;
  return output || '_';
}

function walkTs(root) {
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) return [];
  const files = [];
  function visit(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (entry.isFile() && entry.name.endsWith('.ts') && !entry.name.endsWith('.d.ts')) files.push(full);
    }
  }
  visit(root);
  return files;
}

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { encoding: 'utf8', timeout: options.timeout ?? 120_000, cwd: options.cwd, input: options.input });
  if (result.error) throw result.error;
  return { code: result.status ?? 1, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const out = path.resolve(args.out);
  const summary = [];
  const claimed = new Map();
  const packageNames = (args.packages ?? '').split(/\s+/).filter(Boolean);
  const specs = packageNames.length
    ? packageNames.map((pkg) => ({
      sourceRoot: path.resolve(args['package-root'], pkg, 'src'),
      base: path.resolve(args['package-root'], pkg),
      requestPrefix: pkg,
      outPrefix: pkg,
    }))
    : [{ sourceRoot: path.resolve(args['source-root']), base: path.resolve(args.base), requestPrefix: args['request-prefix'] ?? '', outPrefix: args['out-prefix'] ?? '' }];
  for (const spec of specs) {
   const files = walkTs(spec.sourceRoot);
   if (!files.length && !fs.existsSync(spec.sourceRoot)) {
    summary.push({ path: path.relative(spec.base, spec.sourceRoot), status: 'missing_src' });
   }
   for (const file of files) {
    const rel = path.relative(spec.base, file);
    const normalizedRel = rel.split(path.sep).join('/');
    const requestPath = spec.requestPrefix ? `${spec.requestPrefix}/${normalizedRel}` : normalizedRel;
    const segments = rel.slice(0, -path.extname(rel).length).split(path.sep);
    const prefix = spec.outPrefix ? spec.outPrefix.split('/').filter(Boolean) : [];
    const outRel = path.join(...[...prefix, ...segments].map(snakeSegment)) + '.jac';
    const js = fs.readFileSync(file, 'utf8');
    const converted = run('bun', [args.driver], { input: JSON.stringify({ js, path: requestPath }) });
    let response;
    try { response = JSON.parse(converted.stdout); }
    catch (err) {
      summary.push({ path: requestPath, status: 'driver_error', error: String(err), stderr: converted.stderr.slice(-500) });
      continue;
    }
    if (!response.ok) {
      summary.push({ path: requestPath, status: 'reject', codes: response.codes ?? [], error: response.error });
      continue;
    }
    if (claimed.has(outRel)) {
      console.error(`COLLISION: ${requestPath} and ${claimed.get(outRel)} both snake_case to ${outRel}`);
      summary.push({ path: requestPath, status: 'collision', conflicts_with: claimed.get(outRel) });
      continue;
    }
    claimed.set(outRel, requestPath);
    const outPath = path.join(out, outRel);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    const jac = response.jac ?? '';
    fs.writeFileSync(outPath, jac);
    const checked = run('jac', ['check', outPath], { cwd: args['jac-cwd'], timeout: 90_000 });
    const checkOk = checked.code === 0 && !`${checked.stdout}${checked.stderr}`.includes('FAILED');
    summary.push({ path: requestPath, out: outRel, status: 'floor', bytes: Buffer.byteLength(jac), holes: (jac.match(/JS2JAC-HOLE/g) ?? []).length, jac_check: checkOk });
   }
  }
  const project = run('jac', ['check', out], { cwd: args['jac-cwd'], timeout: Number(args['project-timeout'] ?? 300) * 1000 });
  const projectOk = project.code === 0 && !`${project.stdout}${project.stderr}`.includes('FAILED');
  fs.writeFileSync(args['project-log'], project.stdout + project.stderr);
  fs.writeFileSync(args.summary, JSON.stringify(summary, null, 2));
  const floors = summary.filter((item) => item.status === 'floor');
  const rejects = summary.filter((item) => item.status === 'reject');
  const zeroHole = floors.filter((item) => item.holes === 0);
  const checks = floors.filter((item) => item.jac_check);
  console.log(`floor=${floors.length} reject=${rejects.length} zero_hole=${zeroHole.length} check_pass=${checks.length} project_check=${projectOk ? 'PASS' : 'FAIL'}`);
  for (const item of rejects) console.log(`  REJECT ${item.path} codes=${JSON.stringify(item.codes)} err=${item.error ?? ''}`);
  return 0;
}

try { process.exitCode = main(); }
catch (err) { console.error(`js2jac floor: ${err.message}`); process.exitCode = 2; }
