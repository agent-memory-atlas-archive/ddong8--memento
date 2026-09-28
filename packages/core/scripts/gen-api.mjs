// Regenerates src/api.gen.ts from the Python server's OpenAPI schema, so every
// client gets the server's request and response types without a copy by hand.
//   npm run gen:api            (needs server/.venv, see server/README)
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const server = join(repo, "server");
const python = process.env.MEMENTO_PYTHON ?? join(server, ".venv", "bin", "python");

const spec = execFileSync(
  python,
  ["-c", "import json; from server.main import app; print(json.dumps(app.openapi(), ensure_ascii=False))"],
  { cwd: server, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
);
const out = join(here, "..", "openapi.json");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, spec);

execFileSync(
  process.execPath,
  [join(repo, "node_modules", "openapi-typescript", "bin", "cli.js"), out, "-o", join(here, "..", "src", "api.gen.ts")],
  { stdio: "inherit" },
);
console.log("wrote src/api.gen.ts");
