import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import luaparse from "luaparse";

const root = process.cwd();
const ignoredDirectories = new Set([".git", "dist", "node_modules"]);
const failures = [];
const notes = [];

function fail(message) {
  failures.push(message);
}

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return ignoredDirectories.has(entry.name) ? [] : walk(absolute);
    }
    return [absolute];
  });
}

function relative(file) {
  return path.relative(root, file);
}

const requiredFiles = [
  "info.json",
  "settings.lua",
  "data.lua",
  "control.lua",
  "locale/en/tvh.cfg",
  "README.md",
  "docs/architecture.md",
  "docs/testing.md"
];

for (const file of requiredFiles) {
  if (!fs.existsSync(path.join(root, file))) {
    fail(`missing required file: ${file}`);
  }
}

const infoPath = path.join(root, "info.json");
if (fs.existsSync(infoPath)) {
  try {
    const info = JSON.parse(fs.readFileSync(infoPath, "utf8"));
    if (info.name !== "factorio-the-voyage-home") {
      fail(`info.json name must be factorio-the-voyage-home, got ${info.name}`);
    }
    if (info.factorio_version !== "2.1") {
      fail(`info.json factorio_version must be 2.1, got ${info.factorio_version}`);
    }
    if (!Array.isArray(info.dependencies) || !info.dependencies.some((item) => /^space-age\b/.test(item))) {
      fail("info.json must declare a Space Age dependency");
    }
  } catch (error) {
    fail(`invalid info.json: ${error.message}`);
  }
}

for (const file of walk(root).filter((candidate) => candidate.endsWith(".lua"))) {
  const source = fs.readFileSync(file, "utf8");
  try {
    luaparse.parse(source, {
      comments: false,
      locations: true,
      luaVersion: "5.3",
      scope: true
    });
  } catch (error) {
    fail(`${relative(file)}:${error.line ?? "?"}: Lua syntax error: ${error.message}`);
  }

  if (/\bglobal\s*[.[]/.test(source)) {
    fail(`${relative(file)} uses legacy global state; Factorio 2.x mods must use storage`);
  }
  if (/script\.on_event\(defines\.events\.on_tick/.test(source)) {
    fail(`${relative(file)} registers on_tick; use bounded events/on_nth_tick for this MVP`);
  }
}

const localePath = path.join(root, "locale/en/tvh.cfg");
if (fs.existsSync(localePath)) {
  const seen = new Set();
  let section = "";
  for (const [zeroBasedLine, rawLine] of fs.readFileSync(localePath, "utf8").split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (!line || line.startsWith(";")) continue;
    const sectionMatch = line.match(/^\[([^\]]+)]$/);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    const equals = line.indexOf("=");
    if (equals < 1) {
      fail(`locale/en/tvh.cfg:${zeroBasedLine + 1}: malformed locale entry`);
      continue;
    }
    const key = `${section}.${line.slice(0, equals)}`;
    if (seen.has(key)) fail(`locale/en/tvh.cfg:${zeroBasedLine + 1}: duplicate key ${key}`);
    seen.add(key);
  }
  notes.push(`${seen.size} localized strings`);
}

const luaCount = walk(root).filter((candidate) => candidate.endsWith(".lua")).length;
notes.push(`${luaCount} Lua files parsed`);

if (failures.length > 0) {
  console.error("Validation failed:\n");
  for (const message of failures) console.error(`- ${message}`);
  process.exitCode = 1;
} else {
  console.log(`Validation passed (${notes.join(", ")}).`);
}
