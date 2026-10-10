const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}
function close(server) { return new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())); }

test('ponte resgata ticket uma vez, entrega XML ao Firecast e confirma recibo', async (t) => {
  process.env.SAO_NODE_BRIDGE_TOKEN = 'bridge-test-token';
  process.env.FIRECAST_BRIDGE_TOKEN = 'bridge-test-token';
  process.env.PROXY_ALLOWED_ORIGINS = 'http://localhost:5173';

  let redeemCount = 0;
  let ackBody = null;
  const sao = http.createServer((req, res) => {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      res.setHeader('Content-Type', 'application/json');
      if (req.url === '/api/v1/firecast/transfers/redeem') {
        redeemCount += 1;
        res.end(JSON.stringify({ transferId: 'transfer-1', monsterName: 'Dragão', xml: '<criatura><nome>Dragão</nome><originalSheet>linha 1\nlinha 2</originalSheet></criatura>' }));
      } else if (req.url === '/api/v1/firecast/transfers/transfer-1/ack') {
        ackBody = JSON.parse(body);
        res.end(JSON.stringify({ ok: true }));
      } else res.end(JSON.stringify({ ok: true }));
    });
  });
  const saoPort = await listen(sao);
  process.env.SAO_NODE_BASE_URL = `http://127.0.0.1:${saoPort}`;
  delete require.cache[require.resolve('../gemini-proxy.js')];
  const { app, transfers } = require('../gemini-proxy.js');
  const proxy = http.createServer(app);
  const proxyPort = await listen(proxy);
  t.after(async () => { transfers.clear(); await close(proxy); await close(sao); });

  const queuedResponse = await fetch(`http://127.0.0.1:${proxyPort}/sao-node/transfers`, {
    method: 'POST', headers: { 'content-type': 'application/json', Origin: 'http://localhost:5173' },
    body: JSON.stringify({ ticket: 'one-time-ticket' })
  });
  assert.equal(queuedResponse.status, 202);
  const queued = await queuedResponse.json();
  assert.equal(queued.transferId, 'transfer-1');
  assert.equal(redeemCount, 1);

  const nextResponse = await fetch(`http://127.0.0.1:${proxyPort}/sao-node/transfers/next?consumerId=firecast-test`, {
    headers: { authorization: 'Bearer bridge-test-token' }
  });
  assert.equal(nextResponse.status, 200);
  const delivered = await nextResponse.json();
  assert.match(delivered.xml, /linha 1\nlinha 2/);

  const ackResponse = await fetch(`http://127.0.0.1:${proxyPort}/sao-node/transfers/transfer-1/ack`, {
    method: 'POST', headers: { authorization: 'Bearer bridge-test-token', 'content-type': 'application/json' },
    body: JSON.stringify({ consumerId: 'firecast-test', status: 'applied', message: 'ok' })
  });
  assert.equal(ackResponse.status, 200);
  assert.deepEqual(ackBody, { consumerId: 'firecast-test', status: 'applied', message: 'ok' });

  const receiptResponse = await fetch(`http://127.0.0.1:${proxyPort}/sao-node/transfers/transfer-1`, {
    headers: { authorization: `Bearer ${queued.receiptToken}` }
  });
  assert.equal((await receiptResponse.json()).status, 'applied');
});

test('ponte recusa consumidor sem token e origem de navegador não permitida', async (t) => {
  process.env.SAO_NODE_BRIDGE_TOKEN = 'bridge-test-token';
  process.env.FIRECAST_BRIDGE_TOKEN = 'bridge-test-token';
  process.env.SAO_NODE_BASE_URL = 'http://127.0.0.1:9';
  delete require.cache[require.resolve('../gemini-proxy.js')];
  const { app, transfers } = require('../gemini-proxy.js');
  const proxy = http.createServer(app);
  const proxyPort = await listen(proxy);
  t.after(async () => { transfers.clear(); await close(proxy); });
  const unauthorized = await fetch(`http://127.0.0.1:${proxyPort}/sao-node/transfers/next?consumerId=x`);
  assert.equal(unauthorized.status, 401);
  const origin = await fetch(`http://127.0.0.1:${proxyPort}/sao-node/transfers`, {
    method: 'POST', headers: { 'content-type': 'application/json', Origin: 'https://evil.example' }, body: '{}'
  });
  assert.equal(origin.status, 403);
});
