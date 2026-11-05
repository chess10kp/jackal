import http from 'node:http';

const sid = 'sess-42';
const tools = [{ name: 'echo', description: 'Echo the given text back.', inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } }];
const server = http.createServer((req, res) => {
  if (req.method === 'DELETE') {
    res.writeHead(204, { 'Content-Length': '0' }).end();
    return;
  }
  if (req.method !== 'POST') { res.writeHead(404).end(); return; }
  const chunks = [];
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', () => {
    let message;
    try { message = JSON.parse(Buffer.concat(chunks).toString() || '{}'); }
    catch { res.writeHead(400).end(); return; }
    const id = message.id;
    const method = message.method ?? '';
    const json = (status, value, extra = {}) => {
      const body = JSON.stringify(value);
      res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), ...extra });
      res.end(body);
    };
    if (method === 'initialize') {
      json(200, { jsonrpc: '2.0', id, result: { protocolVersion: '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'fake-http', version: '0' } } }, { 'Mcp-Session-Id': sid });
    } else if (method.startsWith('notifications/')) {
      res.writeHead(202, { 'Content-Length': '0' }).end();
    } else if (req.headers['mcp-session-id'] !== sid) {
      json(400, { jsonrpc: '2.0', id, error: { code: -32001, message: 'missing or stale session id' } });
    } else if (method === 'tools/list') {
      json(200, { jsonrpc: '2.0', id, result: { tools } });
    } else if (method === 'tools/call') {
      const name = message.params?.name ?? '';
      if (name !== 'echo') {
        json(200, { jsonrpc: '2.0', id, error: { code: -32601, message: `unknown tool: ${name}` } });
        return;
      }
      const text = message.params?.arguments?.text ?? '';
      const body = JSON.stringify({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: `echo:${text}` }], isError: false } });
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.end(`event: message\ndata: ${body}\n\n`);
    } else {
      json(200, { jsonrpc: '2.0', id, error: { code: -32601, message: 'method not found' } });
    }
  });
});
server.listen(0, '127.0.0.1', () => process.stdout.write(`READY ${server.address().port}\n`));
