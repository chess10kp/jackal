import http from 'node:http';
import readline from 'node:readline';

const mode = process.argv[2] ?? 'normal';
const send = (value) => process.stdout.write(`${JSON.stringify(value)}\n`);
const emptySchema = { type: 'object', properties: {}, required: [] };
const pageTools = Array.from({ length: 5 }, (_, i) => ({
  name: `t${i}`, description: `page tool ${i}`, inputSchema: emptySchema,
}));

async function runStdio() {
  const lines = readline.createInterface({ input: process.stdin });
  const iter = lines[Symbol.asyncIterator]();
  while (true) {
    const next = await iter.next();
    if (next.done) return;
    let req;
    try { req = JSON.parse(next.value); } catch { continue; }
    const method = req.method ?? '';
    const id = req.id;
    if (mode === 'silent' && method === 'tools/list') continue;
    if (method === 'initialize') {
      send({ jsonrpc: '2.0', id, result: {
        protocolVersion: '2025-06-18', capabilities: { tools: {} },
        serverInfo: { name: 'fake-mcp', version: '0.0.1' },
      } });
    } else if (method === 'notifications/initialized') {
      if (mode === 'dieafter') process.exit(1);
    } else if (method === 'tools/list') {
      if (mode === 'paged') {
        const cursor = Number(req.params?.cursor ?? 0) || 0;
        const tools = pageTools.slice(cursor, cursor + 2);
        const result = { tools };
        if (cursor + 2 < pageTools.length) result.nextCursor = String(cursor + 2);
        send({ jsonrpc: '2.0', id, result });
      } else if (mode === 'requests') {
        send({ jsonrpc: '2.0', id: 's1', method: 'sampling/createMessage', params: { messages: [] } });
        send({ jsonrpc: '2.0', id: 's2', method: 'roots/list', params: {} });
        const replies = [];
        for (let i = 0; i < 2; i++) {
          const reply = await iter.next();
          if (reply.done) break;
          try { replies.push(JSON.parse(reply.value)); } catch { replies.push({}); }
        }
        const ok = replies.length === 2 && replies.every((r) => r.error?.code === -32601);
        send({ jsonrpc: '2.0', id, result: { tools: [{
          name: ok ? 'ok_ping' : 'bad_no_reply', description: 'probe', inputSchema: emptySchema,
        }] } });
      } else if (mode === 'refresh') {
        send({ jsonrpc: '2.0', id, result: { tools: [{
          name: 'beta', description: 'refcount tool', inputSchema: emptySchema,
        }] } });
      } else {
        send({ jsonrpc: '2.0', id, result: { tools: [
          { name: 'echo', description: 'Echo the given text back.', inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } },
          { name: 'boom', description: 'Always fails.', inputSchema: emptySchema },
          { name: 'rich', description: 'Returns mixed content blocks.', inputSchema: emptySchema },
        ] } });
      }
    } else if (method === 'prompts/list') {
      send({ jsonrpc: '2.0', id, result: { prompts: [{ name: 'greet', description: 'Greet someone.', arguments: [{ name: 'who', required: false }] }] } });
    } else if (method === 'prompts/get') {
      const name = req.params?.name ?? '';
      if (name === 'greet') {
        const who = req.params?.arguments?.who ?? 'world';
        send({ jsonrpc: '2.0', id, result: { description: 'A greeting', messages: [{ role: 'user', content: { type: 'text', text: `Hello, ${who}!` } }] } });
      } else {
        send({ jsonrpc: '2.0', id, result: { contents: [{ uri: 'mem://notes/1', mimeType: 'text/plain', text: 'resource one' }] } });
      }
    } else if (method === 'resources/list') {
      send({ jsonrpc: '2.0', id, result: { resources: [
        { uri: 'mem://notes/1', name: 'notes', description: 'The notes.', mimeType: 'text/plain' },
        { uri: 'mem://bin/1', name: 'binary', description: 'Binary data.', mimeType: 'application/octet-stream' },
      ] } });
    } else if (method === 'resources/read') {
      const uri = req.params?.uri ?? '';
      if (uri === 'mem://notes/1') {
        send({ jsonrpc: '2.0', id, result: { contents: [{ uri, mimeType: 'text/plain', text: 'resource one' }] } });
      } else if (uri === 'mem://bin/1') {
        send({ jsonrpc: '2.0', id, result: { contents: [{ uri, mimeType: 'application/octet-stream', blob: 'QUJD' }] } });
      } else {
        send({ jsonrpc: '2.0', id, error: { code: -32602, message: 'unknown resource' } });
      }
    } else if (method === 'tools/call') {
      const name = req.params?.name ?? '';
      const args = req.params?.arguments ?? {};
      if (name === 'echo') {
        send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: `echo:${args.text ?? ''}` }], isError: false } });
      } else if (mode === 'refresh' && name === 'ping') {
        send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: 'pong' }], isError: false } });
      } else if (name === 'rich') {
        send({ jsonrpc: '2.0', id, result: { content: [
          { type: 'image', data: 'aGVsbG8=', mimeType: 'image/png' },
          { type: 'resource', resource: { uri: 'file:///x.txt', mimeType: 'text/plain', text: 'resource body' } },
          { type: 'resource_link', uri: 'file:///y.txt' },
        ], isError: false } });
      } else {
        send({ jsonrpc: '2.0', id, error: { code: -32601, message: `unknown tool: ${name}` } });
      }
    } else if (id !== undefined && id !== null) {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: 'method not found' } });
    }
  }
}

function runHttp() {
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
      const json = (status, value, headers = {}) => {
        const body = JSON.stringify(value);
        res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), ...headers });
        res.end(body);
      };
      if (method === 'initialize') {
        json(200, { jsonrpc: '2.0', id, result: { protocolVersion: '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'fake-http-mcp', version: '0' } } }, { 'Mcp-Session-Id': sid });
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
}

if (mode === 'http') runHttp();
else runStdio().catch((error) => { process.stderr.write(`${error.stack ?? error}\n`); process.exitCode = 1; });
