const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { once } = require('node:events');

const proxyScript = path.resolve(__dirname, '../gemini-proxy.js');

function proxyEnv(port) {
  return { ...process.env, PORT: String(port), GEMINI_API_KEY: '', SAO_NODE_SESSION_COOKIE: '' };
}

test('iniciar em porta ocupada informa o erro e termina com falha', async (t) => {
  const occupied = http.createServer();
  occupied.listen(0, '::');
  await once(occupied, 'listening');
  t.after(() => new Promise((resolve) => occupied.close(resolve)));

  const result = spawnSync(process.execPath, [proxyScript], {
    env: proxyEnv(occupied.address().port), encoding: 'utf8', timeout: 10_000
  });

  assert.ifError(result.error);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /porta .* em uso/i);
  assert.doesNotMatch(result.stdout, /Proxy rodando/);
});

test('iniciar em porta livre mantém o servidor respondendo e informa a porta real', async (t) => {
  const child = spawn(process.execPath, [proxyScript], {
    env: proxyEnv(0), stdio: ['ignore', 'pipe', 'pipe']
  });
  const closed = once(child, 'close');
  t.after(async () => { child.kill(); await closed; });

  let output = '';
  let errors = '';
  child.stderr.setEncoding('utf8').on('data', (chunk) => { errors += chunk; });
  child.stdout.setEncoding('utf8');
  const port = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Proxy não iniciou: ${output}${errors}`)), 10_000);
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
    child.once('exit', (code) => { clearTimeout(timer); reject(new Error(`Proxy encerrou com código ${code}: ${output}${errors}`)); });
    child.stdout.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/Proxy rodando na porta (\d+)/);
      if (match) { clearTimeout(timer); resolve(Number(match[1])); }
    });
  });

  assert.ok(port > 0);
  for (let attempt = 0; attempt < 3; attempt += 1) {
    await new Promise((resolve, reject) => {
      http.get(`http://127.0.0.1:${port}/`, (res) => {
        assert.equal(res.statusCode, 404);
        res.resume();
        res.once('end', resolve);
      }).on('error', reject);
    });
    assert.equal(child.exitCode, null);
  }
});
