import readline from 'node:readline';

if (process.env.FAKE_MCP_FAIL) process.exit(3);

const tools = [
  { name: 'echo', description: 'Echo text back.', inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } },
  { name: 'add', description: 'Add two numbers.', inputSchema: { type: 'object', properties: { a: { type: 'number' }, b: { type: 'number' } }, required: ['a', 'b'] } },
  { name: 'where', description: 'Report the server process working directory.', inputSchema: { type: 'object', properties: {}, required: [] } },
  { name: 'envpeek', description: 'Report FAKE_MCP_TOKEN from the server environment.', inputSchema: { type: 'object', properties: {}, required: [] } },
  { name: 'die', description: 'Reply once, then exit the server process.', inputSchema: { type: 'object', properties: {}, required: [] } },
];
const lines = readline.createInterface({ input: process.stdin });
const send = (id, result, error) => {
  const msg = { jsonrpc: '2.0', id };
  if (error !== undefined) msg.error = error;
  else msg.result = result;
  process.stdout.write(`${JSON.stringify(msg)}\n`);
};

for await (const line of lines) {
  let req;
  try { req = JSON.parse(line); } catch { continue; }
  const id = req.id;
  if (id === undefined || id === null) continue;
  const method = req.method;
  if (method === 'initialize') {
    send(id, { protocolVersion: req.params?.protocolVersion ?? '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'fake', version: '0' } });
  } else if (method === 'tools/list') {
    send(id, { tools });
  } else if (method === 'prompts/list') {
    send(id, { prompts: [{ name: 'greet', description: 'Greet someone.', arguments: [{ name: 'who' }] }] });
  } else if (method === 'prompts/get') {
    const who = req.params?.arguments?.who ?? 'world';
    send(id, { description: 'A greeting', messages: [{ role: 'user', content: { type: 'text', text: `Hello, ${who}!` } }] });
  } else if (method === 'resources/list') {
    send(id, { resources: [{ uri: 'memo://1', name: 'memo', description: 'The memo.', mimeType: 'text/plain' }] });
  } else if (method === 'resources/read') {
    send(id, { contents: [{ uri: 'memo://1', mimeType: 'text/plain', text: 'the memo body' }] });
  } else if (method === 'tools/call') {
    const name = req.params?.name;
    const args = req.params?.arguments ?? {};
    let text;
    if (name === 'echo') text = `echo: ${args.text ?? ''}`;
    else if (name === 'add') text = String((args.a ?? 0) + (args.b ?? 0));
    else if (name === 'where') text = process.cwd();
    else if (name === 'envpeek') text = `token=${process.env.FAKE_MCP_TOKEN ?? 'unset'}`;
    else if (name === 'die') {
      process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: 'dying' }] } })}\n`, () => process.exit(7));
      continue;
    } else {
      send(id, { content: [{ type: 'text', text: 'unknown tool' }], isError: true });
      continue;
    }
    send(id, { content: [{ type: 'text', text }] });
  } else {
    send(id, undefined, { code: -32601, message: 'method not found' });
  }
}
