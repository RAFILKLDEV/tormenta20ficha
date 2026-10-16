const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

function listen(server) { return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port))); }
function close(server) { if (!server.listening) return Promise.resolve(); return new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())); }
async function jsonRequest(base, pathname, options = {}) {
  const response = await fetch(base + pathname, options);
  let body = null;
  if (response.status !== 204) body = await response.json();
  return { response, body };
}
function loadProxy(queueFile) {
  process.env.FIRECAST_QUEUE_FILE = queueFile;
  delete require.cache[require.resolve('../gemini-proxy.js')];
  return require('../gemini-proxy.js');
}

 test('fila local recebe ficha completa, entrega sem auth e confirma somente após ack', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  const { app, transfers } = loadProxy(queueFile);
  const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => { transfers.clear(); await close(server); });
  const payload = { transferId: 'transfer-1', xml: '<criatura><nome>Dragão</nome></criatura>', campaignId: 'camp', monsterId: 'monster-1', monsterName: 'Dragão', imageUrl: 'http://127.0.0.1:3001/api/image', originalSheet: 'full sheet', monster: { stats: { pv: 100 }, attacks: [{ name: 'Mordida' }] } };
  let result = await jsonRequest(base, '/sao-node/transfers', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) });
  assert.equal(result.response.status, 202); assert.equal(result.body.status, 'queued');
  result = await jsonRequest(base, '/sao-node/transfers/next?consumerId=firecast-1');
  assert.equal(result.response.status, 200); assert.deepEqual(result.body.monster, payload.monster); assert.equal(result.body.originalSheet, payload.originalSheet); assert.equal(result.body.imageUrl, payload.imageUrl); assert.equal(result.body.status, 'claimed');
  result = await jsonRequest(base, '/sao-node/transfers/transfer-1');
  assert.equal(result.body.status, 'claimed');
  result = await jsonRequest(base, '/sao-node/transfers/transfer-1/ack', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ consumerId: 'firecast-1', status: 'applied', message: 'criado' }) });
  assert.equal(result.response.status, 200); assert.equal(result.body.status, 'applied');
  result = await jsonRequest(base, '/sao-node/transfers/transfer-1/ack', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ consumerId: 'firecast-1', status: 'applied', message: 'repetido' }) });
  assert.equal(result.response.status, 200); assert.equal(result.body.status, 'applied');
  result = await jsonRequest(base, '/sao-node/transfers/transfer-1'); assert.equal(result.body.status, 'applied');
});

test('normaliza imagem SAO-NODE em monster.media.image quando imageUrl não vem no topo', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  const { app, transfers } = loadProxy(queueFile);
  const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => { transfers.clear(); await close(server); });
  const imageUrl = 'https://cdn.example.test/monstros/dragao.gif';
  let result = await jsonRequest(base, '/sao-node/transfers', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      transferId: 'media-image-1',
      xml: '<criatura><nome>Dragao</nome></criatura>',
      monsterName: 'Dragao',
      monster: { media: { image: imageUrl } }
    })
  });
  assert.equal(result.response.status, 202);
  result = await jsonRequest(base, '/sao-node/transfers/next?consumerId=image-test');
  assert.equal(result.response.status, 200);
  assert.equal(result.body.imageUrl, imageUrl);
});

test('proxy de imagem devolve bytes e MIME e usa cache local', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  const { app, transfers } = loadProxy(queueFile);
  const imageBytes = Buffer.from([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
  const upstream = http.createServer((_req, res) => { res.writeHead(200, { 'content-type': 'image/gif', 'content-length': imageBytes.length }); res.end(imageBytes); });
  const upstreamPort = await listen(upstream);
  const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => { transfers.clear(); await close(server); await close(upstream); });
  const imageUrl = `http://127.0.0.1:${upstreamPort}/monster.gif`;
  let response = await fetch(base + '/sao-node/image?url=' + encodeURIComponent(imageUrl));
  assert.equal(response.status, 200); assert.equal(response.headers.get('content-type'), 'image/gif'); assert.deepEqual(Buffer.from(await response.arrayBuffer()), imageBytes);
  await close(upstream);
  response = await fetch(base + '/sao-node/image?url=' + encodeURIComponent(imageUrl));
  assert.equal(response.status, 200); assert.deepEqual(Buffer.from(await response.arrayBuffer()), imageBytes);
});

test('heartbeat diagnostica Firecast, múltiplos monstros e deduplicação por transferId', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  const { app, transfers } = loadProxy(queueFile); const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => { transfers.clear(); await close(server); });
  let result = await jsonRequest(base, '/sao-node/status'); assert.equal(result.body.firecastConnected, false);
  result = await jsonRequest(base, '/sao-node/consumer/heartbeat', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ consumerId: 'c', ready: false }) }); assert.equal(result.response.status, 200); assert.equal(result.body.firecastConnected, true); assert.equal(result.body.firecastReady, false);
  result = await jsonRequest(base, '/sao-node/status'); assert.equal(result.body.firecastConnected, true); assert.equal(result.body.firecastReady, false); assert.equal(result.body.consumer.id, 'c'); assert.equal(result.body.consumer.ready, false);
  result = await jsonRequest(base, '/sao-node/consumer/heartbeat', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ consumerId: 'c', ready: true }) }); assert.equal(result.body.firecastReady, true); assert.equal(result.body.ready, true);
  result = await jsonRequest(base, '/sao-node/status'); assert.equal(result.body.firecastReady, true); assert.equal(result.body.readyConsumerId, 'c');
  for (const id of ['a', 'b']) {
    result = await jsonRequest(base, '/sao-node/transfers', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ transferId: id, xml: '<criatura><nome>' + id + '</nome></criatura>', monsterName: id }) });
    assert.equal(result.response.status, 202);
  }
  result = await jsonRequest(base, '/sao-node/transfers', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ transferId: 'a', xml: '<different/>', monsterName: 'changed' }) });
  assert.equal(result.response.status, 202); assert.equal(result.body.status, 'queued');
  result = await jsonRequest(base, '/sao-node/transfers/next?consumerId=c'); assert.equal(result.body.transferId, 'a');
  result = await jsonRequest(base, '/sao-node/transfers/a/ack', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ consumerId: 'c', status: 'applied' }) }); assert.equal(result.response.status, 200);
  result = await jsonRequest(base, '/sao-node/transfers/next?consumerId=c'); assert.equal(result.body.transferId, 'b');
});

test('fila persiste após recarregar o módulo e lease expirado volta para queued', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  process.env.FIRECAST_TRANSFER_LEASE_MS = '1';
  let proxy = loadProxy(queueFile); const server = http.createServer(proxy.app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => { proxy.transfers.clear(); await close(server); delete process.env.FIRECAST_TRANSFER_LEASE_MS; });
  let result = await jsonRequest(base, '/sao-node/transfers', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ transferId: 'restart', xml: '<criatura/>', originalSheet: 'preserved' }) }); assert.equal(result.response.status, 202);
  await new Promise((resolve) => setTimeout(resolve, 5));
  result = await jsonRequest(base, '/sao-node/transfers/next?consumerId=old'); assert.equal(result.body.transferId, 'restart');
  await close(server);
  delete require.cache[require.resolve('../gemini-proxy.js')]; proxy = loadProxy(queueFile);
  const restarted = http.createServer(proxy.app); const restartedPort = await listen(restarted); const restartedBase = 'http://127.0.0.1:' + restartedPort;
  t.after(async () => { proxy.transfers.clear(); await close(restarted); });
  result = await jsonRequest(restartedBase, '/sao-node/transfers/restart'); assert.equal(result.body.originalSheet, 'preserved'); assert.equal(result.body.status, 'queued');
});

test('rotas legadas do SAO-NODE continuam publicadas', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  const { app, transfers } = loadProxy(queueFile);
  const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => { transfers.clear(); await close(server); });

  let result = await fetch(base + '/sao-node/monster-xml');
  assert.equal(result.status, 400);
  assert.match(await result.text(), /parametros_ausentes/);

  result = await fetch(base + '/sao-node/transfers', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ticket: 'ticket-legado' })
  });
  assert.equal(result.status, 503);
  assert.match(await result.text(), /sao_node_bridge_nao_configurado/);
});

test('token legado e origem de navegador continuam protegendo o consumidor', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  const previousToken = process.env.FIRECAST_BRIDGE_TOKEN;
  process.env.FIRECAST_BRIDGE_TOKEN = 'bridge-test-token';
  const { app, transfers } = loadProxy(queueFile);
  const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => {
    transfers.clear(); await close(server);
    if (previousToken === undefined) delete process.env.FIRECAST_BRIDGE_TOKEN;
    else process.env.FIRECAST_BRIDGE_TOKEN = previousToken;
  });

  let result = await fetch(base + '/sao-node/transfers/next?consumerId=legacy');
  assert.equal(result.status, 401);
  result = await fetch(base + '/sao-node/consumer/heartbeat', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ consumerId: 'new-firecast', ready: true })
  });
  assert.equal(result.status, 200);
  result = await fetch(base + '/sao-node/transfers/next?consumerId=new-firecast');
  assert.equal(result.status, 204);
  result = await fetch(base + '/sao-node/transfers', {
    method: 'POST', headers: { 'content-type': 'application/json', Origin: 'https://evil.example' },
    body: JSON.stringify({ xml: '<criatura/>' })
  });
  assert.equal(result.status, 403);
});

test('consumidor pronto confirma transferência legada sem repetir o token', async (t) => {
  const queueFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-')), 'queue.json');
  const previousToken = process.env.FIRECAST_BRIDGE_TOKEN;
  process.env.FIRECAST_BRIDGE_TOKEN = 'bridge-test-token';
  const { app, transfers } = loadProxy(queueFile);
  transfers.set('legacy-receipt', {
    transferId: 'legacy-receipt', xml: '<criatura><nome>Legado</nome></criatura>', monsterName: 'Legado',
    status: 'claimed', claimedBy: 'ready-consumer', claimedAt: Date.now(), updatedAt: Date.now(), createdAt: Date.now(),
    message: '', receiptToken: 'legacy-receipt-token'
  });
  const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => {
    transfers.clear(); await close(server);
    if (previousToken === undefined) delete process.env.FIRECAST_BRIDGE_TOKEN;
    else process.env.FIRECAST_BRIDGE_TOKEN = previousToken;
  });
  let result = await jsonRequest(base, '/sao-node/consumer/heartbeat', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ consumerId: 'ready-consumer', ready: true })
  });
  assert.equal(result.response.status, 200);
  result = await jsonRequest(base, '/sao-node/transfers/legacy-receipt/ack', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ consumerId: 'ready-consumer', status: 'applied' })
  });
  assert.equal(result.response.status, 200);
  assert.equal(result.body.status, 'applied');
});

test('falha de persistência não confirma nem perde transferência em memória', async (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'sao-proxy-'));
  const previousToken = process.env.FIRECAST_BRIDGE_TOKEN;
  delete process.env.FIRECAST_BRIDGE_TOKEN;
  const { app, transfers } = loadProxy(directory);
  const server = http.createServer(app); const port = await listen(server); const base = 'http://127.0.0.1:' + port;
  t.after(async () => { transfers.clear(); await close(server); if (previousToken === undefined) delete process.env.FIRECAST_BRIDGE_TOKEN; else process.env.FIRECAST_BRIDGE_TOKEN = previousToken; });
  const result = await jsonRequest(base, '/sao-node/transfers', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ transferId: 'durability', xml: '<criatura/>' })
  });
  assert.equal(result.response.status, 503);
  assert.equal(transfers.has('durability'), false);
});
