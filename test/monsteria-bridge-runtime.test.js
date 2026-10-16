// Runtime tests for the MonsterIA bridge.  These execute the production Lua
// bridge and HTTP wrapper in Fengari with deterministic Firecast substitutes.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");
const interop = require("fengari-interop");

const source = fs.readFileSync(path.join(__dirname, "..", "scripts", "MonsterIA.lua"), "utf8");
const jsonSource = fs.readFileSync(path.join(__dirname, "..", "scripts", "json.lua"), "utf8");
const httpStart = source.indexOf("-- HTTP WRAPPER");
const httpEnd = source.indexOf("local function extractErroXML", httpStart);
const bridgeStart = source.indexOf("-- PONTE SAO-NODE -> FIRECAST");
const bridgeEnd = source.indexOf("-- BOT", bridgeStart);
assert.ok(httpStart >= 0 && httpEnd > httpStart && bridgeStart >= 0 && bridgeEnd > bridgeStart);
const httpSource = source.slice(httpStart, httpEnd);
const bridgeSource = source.slice(bridgeStart, bridgeEnd);

function luaError(L, status) {
  const value = lua.lua_gettop(L) > 0 ? lua.lua_tostring(L, -1) : null;
  return new Error(`Lua error ${status}: ${value ? to_jsstring(value) : "unknown"}`);
}

class Runtime {
  constructor() {
    this.requests = [];
    this.timers = new Map();
    this.nextTimer = 1;
    this.messages = [];
    this.nodes = [];
    this.L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(this.L);
    lauxlib.luaL_requiref(this.L, to_luastring("js"), interop.luaopen_js, 1);
    lua.lua_pop(this.L, 1);
    this.installGlobals();
    this.loadBridge();
  }

  setGlobal(name, value) {
    interop.push(this.L, value);
    lua.lua_setglobal(this.L, to_luastring(name));
  }

  installGlobals() {
    const thisRuntime = this;
    this.setGlobal("__captureRequest", function() {
      const luaRequest = this;
      thisRuntime.requests.push(new Proxy({}, {
        get: (_target, key) => luaRequest.get(key),
        set: (_target, key, value) => { luaRequest.set(key, value); return true; }
      }));
    });
    this.setGlobal("__showMessage", function() {
      thisRuntime.messages.push(String(this || ""));
    });
    this.setGlobal("setTimeout", function(milliseconds) {
      const id = thisRuntime.nextTimer++;
      thisRuntime.timers.set(id, { kind: "timeout", callback: this, milliseconds: Number(milliseconds || 0) });
      return id;
    });
    this.setGlobal("clearTimeout", function() {
      thisRuntime.timers.delete(Number(this));
    });
    this.setGlobal("setInterval", function(milliseconds) {
      const id = thisRuntime.nextTimer++;
      thisRuntime.timers.set(id, { kind: "interval", callback: this, milliseconds: Number(milliseconds || 0) });
      return id;
    });
    this.setGlobal("clearInterval", function() {
      thisRuntime.timers.delete(Number(this));
    });
  }

  loadBridge() {
    const prefix = String.raw`
local internet = {
    newHTTPRequest = function(method, url)
        local request = {
            method = method, url = url, status = 0, statusText = "",
            responseText = "", headers = {}, sent = false, aborted = false
        }
        function request:setRequestHeader(key, value) self.headers[key] = value end
        function request:send(body) self.body = body or ""; self.sent = true end
        function request:abort() self.aborted = true end
        __captureRequest(request)
        return request
    end
}
SAO_NODE_BRIDGE_URL = "http://127.0.0.1:7000"
local BRIDGE_POLL_INTERVAL_MS = 3000
local BRIDGE_REQUEST_TIMEOUT_MS = 10000
local saoNodeBridge = {
    consumerId = nil, timer = nil, enabled = false, targetForm = nil,
    inFlight = false, activeRequest = nil, generation = 0, forms = {},
    seen = {}, pendingAcks = {}, ackRequests = {}, connection = nil, lastStatus = "",
    statusCode = "paused", statusDetail = "", lastTransferDetail = ""
}
local __nodes = {}
local ndb = {
    getChildNodes = function() return __nodes end,
    deleteNode = function(node) node.deleted = true end
}
local Firecast = { getMesaDe = function() return nil end }
local function cleanText(value)
    if value == nil then return "" end
    return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end
local function showMessage(value) __showMessage(value) end
local function aplicarXMLNaFicha(ficha, node, xml)
    if xml == "INVALID" then return false, "xml_invalido" end
    node.appliedXml = xml
    __nodes[#__nodes + 1] = node
    return true
end
function __state(key) return saoNodeBridge[key] end
function __nodeCount() return #__nodes end
function __lastNode() return __nodes[#__nodes] end
function __pendingCount()
    local count = 0
    for _ in pairs(saoNodeBridge.pendingAcks) do count = count + 1 end
    return count
end
function __seedNode(node) __nodes[#__nodes + 1] = node end
`;
    // Execute the exact JSON module used by production in an isolated chunk.
    // Its `return json` then supplies the local table consumed by the bridge.
    const jsonModule = "\nlocal function __jsonModuleFactory()\n" + jsonSource + "\nend\nlocal json = __jsonModuleFactory()\n";
    const code = prefix + jsonModule + httpSource + bridgeSource;
    const status = lauxlib.luaL_loadstring(this.L, to_luastring(code));
    if (status !== lua.LUA_OK) throw luaError(this.L, status);
    const result = lua.lua_pcall(this.L, 0, 0, 0);
    if (result !== lua.LUA_OK) throw luaError(this.L, result);
  }

  call(name, args = []) {
    lua.lua_settop(this.L, 0);
    lua.lua_getglobal(this.L, to_luastring(name));
    for (const arg of args) interop.push(this.L, arg);
    const status = lua.lua_pcall(this.L, args.length, 1, 0);
    if (status !== lua.LUA_OK) throw luaError(this.L, status);
    const value = interop.tojs(this.L, -1);
    lua.lua_settop(this.L, 0);
    return value;
  }

  state(key) { return this.call("__state", [key]); }
  pendingCount() { return this.call("__pendingCount"); }
  nodeCount() { return this.call("__nodeCount"); }
  lastNode() { return this.call("__lastNode"); }
  seedNode(node) { this.call("__seedNode", [node]); }
  start(form) { this.call("alternarRecepcaoSaoNode", [form]); }
  register(form) { this.call("iniciarRecepcaoSaoNode", [form]); }
  stop(form) { this.call("alternarRecepcaoSaoNode", [form]); }
  unload(form) { this.call("finalizarRecepcaoSaoNode", [form]); }

  fireTimer(id) {
    const timer = this.timers.get(id);
    if (!timer) return false;
    if (timer.kind === "timeout") this.timers.delete(id);
    timer.callback();
    return true;
  }

  fireOneTimer(kind) {
    const entry = [...this.timers.entries()].find(([, timer]) => !kind || timer.kind === kind);
    return entry ? this.fireTimer(entry[0]) : false;
  }

  latestRequest() { return this.requests[this.requests.length - 1]; }

  respond(request, status, body) {
    assert.ok(request, "request expected");
    request.status = status;
    request.responseText = body || "";
    if (typeof request.onResponse === "function") request.onResponse();
  }

  error(request, message = "network") {
    request.status = 0;
    request.responseText = message;
    if (typeof request.onError === "function") request.onError(message);
  }
}

function formFixture() {
  const form = {
    handle: 1,
    isShowing: true,
    __appendCount: 0,
    __children: [],
    box: { node: null, visible: false },
    sheet: { lista: {} },
    rclMonstros: {
      selectedNode: null,
      append: function() {
        form.__appendCount += 1;
        const node = { nome: "", deleted: false };
        form.__children.push(node);
        return node;
      }
    }
  };
  return form;
}

function heartbeatResponse(runtime) {
  const request = runtime.latestRequest();
  runtime.respond(request, 200, '{"ok":true,"firecastConnected":true,"firecastReady":true}');
  return runtime.latestRequest();
}

test("começa pausado e só envia heartbeat depois de ativar", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  assert.equal(runtime.state("enabled"), false);
  assert.equal(runtime.state("timer"), undefined);
  assert.equal(runtime.requests.length, 0);
  runtime.start(form);
  assert.equal(runtime.state("enabled"), true);
  assert.equal(runtime.state("targetForm"), form);
  assert.equal(runtime.requests.length, 1);
  assert.equal(runtime.latestRequest().url, "http://127.0.0.1:7000/sao-node/consumer/heartbeat");
});

test("aba oculta continua recebendo enquanto o destino está carregado", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  form.isShowing = false;
  const next = heartbeatResponse(runtime);
  runtime.respond(next, 204, "");
  assert.equal(runtime.state("enabled"), true);
  assert.equal(runtime.state("targetForm"), form);
  assert.equal(runtime.state("statusCode"), "waiting");
  assert.notEqual(runtime.state("timer"), undefined);
});

test("pausar ou descarregar cancela polling e aborta requisição ativa", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const active = runtime.latestRequest();
  runtime.stop(form);
  assert.equal(active.aborted, true);
  assert.equal(runtime.state("enabled"), false);
  assert.equal(runtime.state("timer"), undefined);

  const runtime2 = new Runtime();
  const form2 = formFixture();
  runtime2.register(form2);
  runtime2.start(form2);
  const active2 = runtime2.latestRequest();
  runtime2.unload(form2);
  assert.equal(active2.aborted, true);
  assert.equal(runtime2.state("enabled"), false);
  assert.equal(runtime2.state("targetForm"), undefined);
});

test("timeout encerra tentativa e callback atrasado não reativa o polling", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const request = runtime.latestRequest();
  const timeout = [...runtime.timers.entries()].find(([, timer]) => timer.kind === "timeout");
  assert.ok(timeout);
  runtime.fireTimer(timeout[0]);
  assert.equal(request.aborted, true);
  assert.equal(runtime.state("inFlight"), false);
  assert.equal(runtime.state("statusCode"), "offline");
  const count = runtime.requests.length;
  runtime.respond(request, 200, '{"ok":true}');
  assert.equal(runtime.requests.length, count);
  assert.equal(runtime.state("statusCode"), "offline");
});

test("ACK só vira Recebido com resposta positiva; ACK perdido é reencaminhado", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const next = heartbeatResponse(runtime);
  runtime.respond(next, 200, '{"transferId":"t1","xml":"XML","monsterName":"Cavalo"}');
  const ack = runtime.latestRequest();
  assert.equal(ack.url, "http://127.0.0.1:7000/sao-node/transfers/t1/ack");
  assert.equal(runtime.state("statusCode"), "confirming");
  assert.equal(runtime.pendingCount(), 1);
  runtime.respond(ack, 200, '{"ok":false,"status":"applied"}');
  assert.equal(runtime.pendingCount(), 1);
  assert.equal(runtime.state("statusCode"), "error");
  const beforeRetry = runtime.requests.length;
  runtime.fireOneTimer("interval");
  assert.ok(runtime.requests.length > beforeRetry);
  const retryAck = [...runtime.requests].reverse().find((item) => /\/ack$/.test(item.url));
  assert.ok(retryAck);
  runtime.respond(retryAck, 200, '{"ok":true,"status":"applied"}');
  assert.equal(runtime.pendingCount(), 0);
  assert.equal(runtime.state("statusCode"), "received");
});

test("aplica imageUrl da transferência no campo imagemURL do registro", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const next = heartbeatResponse(runtime);
  const imageUrl = "https://cdn.example.test/monstros/cavalo.gif";
  runtime.respond(next, 200, JSON.stringify({
    transferId: "image-url-1",
    xml: "<criatura><nome>Cavalo</nome></criatura>",
    monsterName: "Cavalo",
    imageUrl
  }));

  assert.equal(form.__appendCount, 1);
  assert.equal(form.__children[0].imagemURL, imageUrl);
});

test("aceita a imagem no formato SAO-NODE monster.media.image quando imageUrl não vem no topo", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const next = heartbeatResponse(runtime);
  const imageUrl = "https://cdn.example.test/monstros/dragao.gif";
  runtime.respond(next, 200, JSON.stringify({
    transferId: "image-media-1",
    xml: "<criatura><nome>Dragao</nome></criatura>",
    monsterName: "Dragao",
    monster: { media: { image: imageUrl } }
  }));

  assert.equal(form.__appendCount, 1);
  assert.equal(form.__children[0].imagemURL, imageUrl);
});

test("deduplica por saoNodeTransferId quando a ponte é reiniciada", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  let next = heartbeatResponse(runtime);
  runtime.respond(next, 200, '{"transferId":"persist-1","xml":"XML","monsterName":"Persistente"}');
  const ack = runtime.latestRequest();
  runtime.respond(ack, 200, '{"ok":true,"status":"applied"}');
  const created = form.__appendCount;
  const existingNode = form.__children[0] || runtime.lastNode();

  const restarted = new Runtime();
  restarted.seedNode(existingNode);
  restarted.register(form);
  restarted.start(form);
  next = heartbeatResponse(restarted);
  restarted.respond(next, 200, '{"transferId":"persist-1","xml":"XML","monsterName":"Persistente"}');
  assert.equal(form.__appendCount, created);
  const duplicateAck = [...restarted.requests].reverse().find((item) => /\/ack$/.test(item.url));
  assert.ok(duplicateAck);
});

test("XML inválido remove o registro novo e envia ACK failed", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const next = heartbeatResponse(runtime);
  runtime.respond(next, 200, '{"transferId":"bad-xml","xml":"INVALID","monsterName":"Quebrado"}');
  const node = form.__children[0];
  assert.equal(form.__appendCount, 1);
  assert.equal(node.deleted, true);
  const ack = runtime.latestRequest();
  assert.match(ack.body, /failed/);
});

test("resposta JSON inválida identifica a etapa e não cria registro", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const next = heartbeatResponse(runtime);
  runtime.respond(next, 200, "<resposta quebrada>");
  assert.equal(form.__appendCount, 0);
  assert.equal(runtime.state("statusCode"), "error");
  assert.match(runtime.state("statusDetail"), /Consulta/);
});

test("ACK atrasado depois de pausar não muda o status nem confirma a ficha", () => {
  const runtime = new Runtime();
  const form = formFixture();
  runtime.register(form);
  runtime.start(form);
  const next = heartbeatResponse(runtime);
  runtime.respond(next, 200, '{"transferId":"late-ack","xml":"XML","monsterName":"Atrasado"}');
  const ack = runtime.latestRequest();
  runtime.stop(form);
  runtime.respond(ack, 200, '{"ok":true,"status":"applied"}');
  assert.equal(runtime.state("statusCode"), "paused");
  assert.equal(runtime.pendingCount(), 1);
});

