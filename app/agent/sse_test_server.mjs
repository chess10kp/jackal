import http from 'node:http';
import fs from 'node:fs';

const mode = process.argv[2] ?? 'ok';
const readyFile = process.argv[3];
let posts = 0;
const server = http.createServer((req, res) => {
  if (req.method !== 'POST') { res.writeHead(404).end(); return; }
  req.resume();
  req.on('end', () => {
    posts += 1;
    if (mode === 'boom' || (mode === 'flaky' && posts === 1)) {
      res.writeHead(503);
      res.end(mode === 'flaky' ? 'flaky upstream' : 'upstream down');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"hello"}}]}\n\n');
    res.end('data: [DONE]\n\n');
  });
});
server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(readyFile, String(server.address().port));
});
process.once('SIGTERM', () => server.close(() => process.exit(0)));
