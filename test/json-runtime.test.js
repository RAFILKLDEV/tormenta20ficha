const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");
const interop = require("fengari-interop");

const source = fs.readFileSync(path.join(__dirname, "..", "scripts", "json.lua"), "utf8");

function createRuntime() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lauxlib.luaL_requiref(L, to_luastring("js"), interop.luaopen_js, 1);
  lua.lua_pop(L, 1);
  const load = lauxlib.luaL_loadstring(L, to_luastring(source));
  assert.equal(load, lua.LUA_OK);
  const call = lua.lua_pcall(L, 0, 1, 0);
  assert.equal(call, lua.LUA_OK);
  const json = interop.tojs(L, -1);
  lua.lua_settop(L, 0);
  return { L, json };
}

function invoke(runtime, expression) {
  const { L, json } = runtime;
  interop.push(L, json);
  lua.lua_setglobal(L, to_luastring("json"));
  const status = lauxlib.luaL_loadstring(L, to_luastring("return " + expression));
  assert.equal(status, lua.LUA_OK);
  const result = lua.lua_pcall(L, 0, 1, 0);
  if (result !== lua.LUA_OK) {
    const message = lua.lua_gettop(L) ? to_jsstring(lua.lua_tostring(L, -1)) : "unknown";
    throw new Error(message);
  }
  const value = interop.tojs(L, -1);
  lua.lua_settop(L, 0);
  return value;
}

test("json.lua decodifica payload da ponte sem executar código", () => {
  const runtime = createRuntime();
  assert.equal(invoke(runtime, 'json.decode("{\\"ok\\":true,\\"status\\":\\"applied\\",\\"nested\\":{\\"id\\":7}} ").nested.id'), 7);
  assert.equal(invoke(runtime, 'json.decode("[1,2,3]")[2]'), 2);
  assert.equal(invoke(runtime, String.raw`json.decode([[{"text":"linha\ncom\"aspas"}]]).text`), "linha\ncom\"aspas");
  assert.throws(() => invoke(runtime, 'json.decode("{\\"x\\": (function() os.execute(\\"bad\\") end)()}")'), /unexpected|expected|invalid/);
  assert.throws(() => invoke(runtime, 'json.decode("{\\"x\\":true" )'), /expected|unexpected/);
});
