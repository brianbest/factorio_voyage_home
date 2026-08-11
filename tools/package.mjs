import childProcess from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const info = JSON.parse(fs.readFileSync(path.join(root, "info.json"), "utf8"));
const directoryName = `${info.name}_${info.version}`;
const dist = path.join(root, "dist");
const stagingRoot = fs.mkdtempSync(path.join(os.tmpdir(), "tvh-package-"));
const staging = path.join(stagingRoot, directoryName);
const archive = path.join(dist, `${directoryName}.zip`);

const excluded = new Set([
  ".git",
  ".gitignore",
  "dist",
  "node_modules",
  "package-lock.json",
  "package.json",
  "tests",
  "tools"
]);

fs.mkdirSync(dist, { recursive: true });
fs.cpSync(root, staging, {
  recursive: true,
  filter(source) {
    if (source === root) return true;
    return !excluded.has(path.relative(root, source).split(path.sep)[0]);
  }
});

if (fs.existsSync(archive)) fs.rmSync(archive);
childProcess.execFileSync("zip", ["-qr", archive, directoryName], { cwd: stagingRoot });
fs.rmSync(stagingRoot, { recursive: true, force: true });

console.log(path.relative(root, archive));
