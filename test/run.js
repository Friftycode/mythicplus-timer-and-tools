// Test runner: syntax-checks every addon file, then runs them under fengari
// against the mock client and asserts on what they drew. The file list comes
// from the .toc, in .toc order, so it matches the client's load order.
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");
const { lua, lauxlib, lualib, to_jsstring } = require("fengari");

const ROOT = path.join(__dirname, "..");
const ADDON_DIR = path.join(ROOT, "MythicPlusTimerandTools");
const TOC = path.join(ADDON_DIR, "MythicPlusTimerandTools.toc");

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

const luaFiles = fs
  .readFileSync(TOC, "utf8")
  .split(/\r?\n/)
  .map((l) => l.trim())
  .filter((l) => /\.lua$/i.test(l) && !l.startsWith("#"))
  .map((l) => path.join(ADDON_DIR, l));

if (!luaFiles.length) fail("no .lua files listed in MythicPlusTimerandTools.toc");

// Anything in the folder the .toc forgot would never load in game either.
const onDisk = fs.readdirSync(ADDON_DIR).filter((f) => /\.lua$/i.test(f));
const listed = new Set(luaFiles.map((f) => path.basename(f)));
const orphans = onDisk.filter((f) => !listed.has(f));
if (orphans.length) fail("not listed in MythicPlusTimerandTools.toc (would never load): " + orphans.join(", "));

// 1. Syntax gate.
let totalLines = 0;
for (const file of luaFiles) {
  const source = fs.readFileSync(file, "utf8");
  totalLines += source.split("\n").length;
  try {
    luaparse.parse(source, { luaVersion: "5.1" });
  } catch (e) {
    fail("luaparse " + path.basename(file) + ": " + e.message);
  }
}
console.log(
  "luaparse: OK (" + luaFiles.length + " files, " + totalLines + " lines)"
);

// 2. Behavior. Each chunk is loaded as raw bytes so the UTF-8 box-drawing
//    characters in the comments survive verbatim.
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(file, addonArgs) {
  const buf = fs.readFileSync(file);
  if (lauxlib.luaL_loadbuffer(L, buf, buf.length, "@" + path.basename(file)) !== lua.LUA_OK) {
    fail("load " + path.basename(file) + ": " + to_jsstring(lua.lua_tostring(L, -1)));
  }
  // The client calls each file with (addonName, addonTable) -- the same shared
  // table each time -- so hand it over the same way.
  let nargs = 0;
  if (addonArgs) {
    lua.lua_pushliteral(L, "MythicPlusTimerandTools");
    lua.lua_getglobal(L, "MythicPlusTimerNamespace");
    nargs = 2;
  }
  if (lua.lua_pcall(L, nargs, 0, 0) !== lua.LUA_OK) {
    fail("run " + path.basename(file) + ": " + to_jsstring(lua.lua_tostring(L, -1)));
  }
}

run(path.join(__dirname, "mockwow.lua"));
lua.lua_newtable(L);
lua.lua_setglobal(L, "MythicPlusTimerNamespace");
for (const file of luaFiles) run(file, true);
run(path.join(__dirname, "spec.lua"));

// Pull Mock.report / Mock.exitCode back out.
lua.lua_getglobal(L, "Mock");
lua.lua_getfield(L, -1, "report");
const report = to_jsstring(lua.lua_tostring(L, -1) || "");
lua.lua_pop(L, 1);
lua.lua_getfield(L, -1, "exitCode");
const code = lua.lua_tointeger(L, -1);

console.log(report);
process.exit(code === 0 ? 0 : 1);
