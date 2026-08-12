import childProcess from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";

const MOD_NAME = "factorio-the-voyage-home";
const TEST_SEED = "246813579";
const TEST_TICKS = "180";
const excluded = new Set([
  ".git",
  ".gitignore",
  "dist",
  "node_modules",
  "package-lock.json",
  "package.json",
  "tests",
  "tools",
]);

function fail(message) {
  console.error(`Live Factorio smoke test failed: ${message}`);
  process.exitCode = 1;
}

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
  return value;
}

function executableCandidates() {
  const candidates = [];
  if (process.env.FACTORIO_BIN) candidates.push(process.env.FACTORIO_BIN);

  const which = childProcess.spawnSync("which", ["factorio"], { encoding: "utf8" });
  if (which.status === 0 && which.stdout.trim()) candidates.push(which.stdout.trim());

  if (process.platform === "darwin") {
    candidates.push(
      path.join(
        os.homedir(),
        "Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio",
      ),
      "/Applications/factorio.app/Contents/MacOS/factorio",
      "/Applications/Factorio.app/Contents/MacOS/factorio",
    );
  }

  return [...new Set(candidates)];
}

function locateFactorio() {
  const explicit = argument("--factorio");
  const candidates = explicit ? [explicit] : executableCandidates();
  const executable = candidates.find((candidate) => fs.existsSync(candidate));
  if (!executable) {
    throw new Error(
      "Factorio executable not found; pass --factorio /path/to/factorio or set FACTORIO_BIN",
    );
  }
  return path.resolve(executable);
}

function run(executable, args, options = {}) {
  console.log(`\n$ ${executable} ${args.join(" ")}`);
  const result = childProcess.spawnSync(executable, args, {
    cwd: options.cwd,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail = options.capture ? `\n${result.stdout}${result.stderr}` : "";
    throw new Error(`Factorio exited with status ${result.status}${detail}`);
  }
  return result;
}

function versionOf(executable) {
  const result = run(executable, ["--version"], { capture: true });
  const output = `${result.stdout}${result.stderr}`;
  process.stdout.write(output);
  const match = output.match(/Version:\s+(\d+\.\d+\.\d+)/);
  if (!match) throw new Error("could not parse Factorio version output");
  return match[1];
}

function engineDataDirectory(executable) {
  if (process.platform === "darwin") {
    const candidate = path.resolve(path.dirname(executable), "..", "data");
    if (fs.existsSync(candidate)) return candidate;
  }
  const candidate = path.resolve(path.dirname(executable), "..", "data");
  if (fs.existsSync(candidate)) return candidate;
  throw new Error("could not locate Factorio's data directory beside the executable");
}

function copyMod(source, destination) {
  fs.cpSync(source, destination, {
    recursive: true,
    filter(candidate) {
      if (candidate === source) return true;
      return !excluded.has(path.relative(source, candidate).split(path.sep)[0]);
    },
  });
}

function applyFactorio20CompatibilityShim(modDirectory) {
  const infoPath = path.join(modDirectory, "info.json");
  const info = JSON.parse(fs.readFileSync(infoPath, "utf8"));
  info.factorio_version = "2.0";
  info.dependencies = info.dependencies.map((dependency) => dependency.replace(/>= 2\.1\.0/g, ">= 2.0.0"));
  fs.writeFileSync(infoPath, `${JSON.stringify(info, null, 2)}\n`);

  const vesselPath = path.join(modDirectory, "prototypes/vessel.lua");
  const vessel = fs.readFileSync(vesselPath, "utf8");
  const oldField = '    categories = {"tvh-interstellar-vessel-crafting"},';
  const newField = '    category = "tvh-interstellar-vessel-crafting",';
  if (!vessel.includes(oldField)) {
    throw new Error("2.0 shim expected exactly one 2.1 recipe categories field");
  }
  const converted = vessel.replace(oldField, newField);
  if (converted.includes(oldField)) {
    throw new Error("2.0 shim did not uniquely convert the recipe categories field");
  }
  fs.writeFileSync(vesselPath, converted);
}

function configureTestDirectory(testRoot, dataDirectory, modDirectory) {
  const writeData = path.join(testRoot, "user-data");
  const mods = path.join(testRoot, "mods");
  fs.mkdirSync(writeData, { recursive: true });
  fs.mkdirSync(mods, { recursive: true });

  const configPath = path.join(testRoot, "config.ini");
  fs.writeFileSync(
    configPath,
    `[path]\nread-data=${dataDirectory}\nwrite-data=${writeData}\n\n[general]\nlocale=en\n`,
  );
  fs.writeFileSync(
    path.join(mods, "mod-list.json"),
    `${JSON.stringify({
      mods: [
        { name: "base", enabled: true },
        { name: "elevated-rails", enabled: true },
        { name: "quality", enabled: true },
        { name: "space-age", enabled: true },
        { name: MOD_NAME, enabled: true },
      ],
    }, null, 2)}\n`,
  );
  fs.renameSync(modDirectory, path.join(mods, path.basename(modDirectory)));
  return { configPath, mods, writeData };
}

function assertSource(source) {
  const infoPath = path.join(source, "info.json");
  if (!fs.existsSync(infoPath)) throw new Error(`not a Factorio mod source tree: ${source}`);
  const info = JSON.parse(fs.readFileSync(infoPath, "utf8"));
  if (info.name !== MOD_NAME) throw new Error(`unexpected mod name: ${info.name}`);
  return info;
}

let testRoot;
try {
  const source = path.resolve(argument("--source") ?? process.cwd());
  const sourceInfo = assertSource(source);
  const executable = locateFactorio();
  const engineVersion = versionOf(executable);
  const engineLine = engineVersion.split(".").slice(0, 2).join(".");
  const targetLine = sourceInfo.factorio_version;

  testRoot = fs.mkdtempSync(path.join(os.tmpdir(), "tvh-factorio-live-"));
  const stagedMod = path.join(testRoot, `${sourceInfo.name}_${sourceInfo.version}`);
  copyMod(source, stagedMod);

  let qualification = "target acceptance";
  if (engineLine !== targetLine) {
    if (engineLine === "2.0" && targetLine === "2.1") {
      applyFactorio20CompatibilityShim(stagedMod);
      qualification = "2.0 compatibility smoke only; not 2.1 acceptance";
    } else {
      throw new Error(`Factorio ${engineVersion} cannot test a Factorio ${targetLine} mod`);
    }
  }

  const dataDirectory = engineDataDirectory(executable);
  const configured = configureTestDirectory(testRoot, dataDirectory, stagedMod);
  const save = path.join(configured.writeData, "saves", "tvh-live-smoke.zip");
  fs.mkdirSync(path.dirname(save), { recursive: true });

  console.log(`\nEngine: Factorio ${engineVersion}`);
  console.log(`Source: ${source}`);
  console.log(`Qualification: ${qualification}`);
  console.log(`Isolated user data: ${configured.writeData}`);

  const common = [
    "--config", configured.configPath,
    "--mod-directory", configured.mods,
    "--disable-audio",
    "--no-log-rotation",
  ];
  run(executable, [...common, "--create", save, "--map-gen-seed", TEST_SEED]);
  if (!fs.existsSync(save)) throw new Error("Factorio exited successfully but did not create the smoke-test save");

  run(executable, [
    ...common,
    "--benchmark", save,
    "--benchmark-ticks", TEST_TICKS,
    "--benchmark-runs", "1",
    "--benchmark-sanitize",
  ]);

  console.log("\nLive Factorio smoke test passed.");
  console.log("- Real engine data stage loaded the mod and Space Age dependencies.");
  console.log("- A deterministic disposable map was created successfully.");
  console.log(`- The saved runtime executed ${TEST_TICKS} ticks without a script error.`);
  console.log(`- Evidence level: ${qualification}.`);
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
  if (testRoot) console.error(`Preserved failed test workspace: ${testRoot}`);
} finally {
  if (testRoot && process.exitCode !== 1 && process.env.TVH_KEEP_LIVE_TEST !== "1") {
    const expectedPrefix = path.join(os.tmpdir(), "tvh-factorio-live-");
    if (!testRoot.startsWith(expectedPrefix)) throw new Error(`refusing to remove unexpected path: ${testRoot}`);
    fs.rmSync(testRoot, { recursive: true, force: true });
  } else if (testRoot && process.env.TVH_KEEP_LIVE_TEST === "1") {
    console.log(`Preserved test workspace: ${testRoot}`);
  }
}
