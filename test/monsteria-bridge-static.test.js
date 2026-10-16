const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const lua = fs.readFileSync(path.join(root, 'scripts', 'MonsterIA.lua'), 'utf8');
const lfm = fs.readFileSync(path.join(root, 'MosterIA.lfm'), 'utf8');

function bridgeSource() {
  const start = lua.indexOf('-- PONTE SAO-NODE -> FIRECAST');
  const end = lua.indexOf('-- BOT', start);
  assert.ok(start >= 0 && end > start, 'ponte MonsterIA não encontrada');
  return lua.slice(start, end);
}

test('ponte MonsterIA usa HTTP local e preserva a consulta manual', () => {
  const bridge = bridgeSource();
  assert.match(lua, /SAO_NODE_BRIDGE_URL\s*=\s*SAO_NODE_BRIDGE_URL\s+or\s+"http:\/\/127\.0\.0\.1:7000"/);
  assert.doesNotMatch(bridge, /SAO_NODE_(?:BRIDGE_TOKEN|SESSION_COOKIE)|FIRECAST_BRIDGE_TOKEN/);
  assert.match(lua, /SAO_NODE_PROXY_URL/);
  assert.match(lua, /function askSaoNodeAndFill/);
  assert.match(lfm, /edtSaoNodeCampaignId/);
  assert.match(lfm, /edtSaoNodeMonsterId/);
  assert.match(bridge, /httpPOST\(/);
  assert.doesNotMatch(bridge, /Authorization|Bearer|dialogs\.inputQuery/);
  assert.match(lfm, /<event name="onShow">[\s\S]*iniciarRecepcaoSaoNode/);
  assert.match(lfm, /<event name="onNodeUnready">[\s\S]*finalizarRecepcaoSaoNode/);
  assert.match(lfm, /name="btnAguardarFichas"/);
  assert.match(lfm, /alternarRecepcaoSaoNode\(self\)/);
  assert.match(lfm, /name="lblSaoNodeStatus"/);
  assert.match(lfm, /name="imgImagem"\s+field="imagemURL"/);
  assert.doesNotMatch(lfm, /onHide[\s\S]*finalizarRecepcaoSaoNode/);
  assert.doesNotMatch(bridge, /form\.isShowing\s*~=/);
});

test('ponte cria registro novo e só confirma depois de aplicar a ficha', () => {
  const bridge = bridgeSource();
  const append = bridge.indexOf('ficha.rclMonstros:append()');
  const apply = bridge.indexOf('aplicarXMLNaFicha(ficha, node, xml)');
  const ack = bridge.indexOf('bridgeAck(transferId, "applied"', apply);
  assert.ok(append >= 0 && apply > append && ack > apply);
  assert.match(bridge, /node\.originalSheet\s*=\s*originalSheet/);
  assert.match(bridge, /node\.saoNodeSourceJson\s*=\s*sourceJson/);
  assert.match(bridge, /node\.imagemURL\s*=\s*imageURLForSource\(imageUrl\)/);
  assert.match(lua, /source\.media/);
  assert.match(lua, /function imageURLForSource/);
});

test('polling é singleton e é encerrado quando não há janelas', () => {
  const bridge = bridgeSource();
  assert.match(bridge, /saoNodeBridge\.inFlight/);
  assert.match(bridge, /saoNodeBridge\.timer\s*==\s*nil/);
  assert.match(bridge, /clearInterval\(saoNodeBridge\.timer\)/);
  assert.match(bridge, /function finalizarRecepcaoSaoNode/);
  assert.match(bridge, /status or 0\)\s*[=~]=\s*204/);
  assert.match(bridge, /pendingAcks/);
  assert.match(bridge, /ready\s*=\s*true/);
  assert.match(lua, /BRIDGE_REQUEST_TIMEOUT_MS/);
  assert.match(lua, /req:abort/);
  assert.match(bridge, /saoNodeTransferId/);
  assert.match(bridge, /bridgeFindExistingNode/);
  assert.match(bridge, /cycle\s*~=\s*saoNodeBridge\.generation/);
  assert.match(bridge, /resposta invalida do proxy/);
  assert.match(bridge, /Confirmacao:/);
});
