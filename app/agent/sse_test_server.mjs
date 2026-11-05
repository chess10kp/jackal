import http from 'node:http';

const mode = process.argv[2] ?? 'ok';
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
  process.stdout.write(`READY ${server.address().port}\n`);
});
process.once('SIGTERM', () => server.close(() => process.exit(0)));
