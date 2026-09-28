import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, expect, it } from "vitest";

import {
  applyProfileInjection,
  isValidProfileBlock,
  removeProfileBlock,
  upsertProfileBlock,
  type ProfileTarget,
} from "../src/profile-inject.js";

const blockV1 = "<!-- memento:begin v1 · x -->\n## 关于我\n\n- 用中文回复\n<!-- memento:end -->\n";
const blockV2 = "<!-- memento:begin v2 · x -->\n## 关于我\n\n- 用中文回复\n- 只走 GitOps\n<!-- memento:end -->\n";

let tmp: string;
let files: Record<string, ProfileTarget>;
let statePath: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "profile_inject_"));
  for (const h of ["claude", "codex", "gemini"]) mkdirSync(join(tmp, h));
  files = {
    claude_code: { toolHome: join(tmp, "claude"), file: join(tmp, "claude", "CLAUDE.md") },
    codex: { toolHome: join(tmp, "codex"), file: join(tmp, "codex", "AGENTS.md") },
    antigravity: { toolHome: join(tmp, "gemini"), file: join(tmp, "gemini", "GEMINI.md") },
    hermes: { toolHome: join(tmp, "not-installed"), file: join(tmp, "not-installed", "SOUL.md") },
  };
  statePath = join(tmp, "state.json");
});

afterEach(() => rmSync(tmp, { recursive: true, force: true }));

const run = (version: number | null, block: string | null, targets: string[]) =>
  applyProfileInjection({ version, block, targets, files, statePath });
const read = (tool: string) => readFileSync(files[tool]!.file, "utf8");

it("upsert appends to existing text, then replaces in place", () => {
  const once = upsertProfileBlock("# mine\n\nkeep\n", blockV1)!;
  expect(once.startsWith("# mine\n\nkeep")).toBe(true);
  const twice = upsertProfileBlock(once, blockV2)!;
  expect(twice.split("memento:begin").length - 1).toBe(1);
  expect(twice).toContain("GitOps");
});

it("damaged markers are refused, not guessed at", () => {
  const damaged = "# mine\n<!-- memento:begin v1 -->\nhalf a block\n";
  expect(upsertProfileBlock(damaged, blockV1)).toBeNull();
  expect(removeProfileBlock(damaged)).toBeNull();
});

it("block validation rejects nested or missing markers", () => {
  expect(isValidProfileBlock(blockV1)).toBe(true);
  expect(isValidProfileBlock(blockV1 + blockV2)).toBe(false);
  expect(isValidProfileBlock("no markers")).toBe(false);
  expect(isValidProfileBlock(null)).toBe(false);
});

it("write, update, and remove round trip leaves user files untouched", async () => {
  writeFileSync(files.codex!.file, "# my codex rules\n");
  expect(await run(1, blockV1, ["claude_code", "codex", "hermes"])).toEqual({
    claude_code: "written",
    codex: "written",
    hermes: "skipped: tool not installed",
  });
  expect(read("claude_code")).toBe(blockV1);
  expect(read("codex").startsWith("# my codex rules")).toBe(true);
  expect(readFileSync(`${files.codex!.file}.memento.bak`, "utf8")).toBe("# my codex rules\n");

  expect(await run(1, blockV1, ["claude_code", "codex"])).toEqual({ claude_code: "unchanged", codex: "unchanged" });
  expect((await run(2, blockV2, ["claude_code", "codex"])).codex).toBe("written");
  expect(read("codex")).toContain("GitOps");

  // Switched off in the app: the file we created goes away, the user's file is restored.
  expect(await run(2, blockV2, [])).toEqual({ claude_code: "removed", codex: "removed" });
  expect(existsSync(files.claude_code!.file)).toBe(false);
  expect(read("codex")).toBe("# my codex rules\n");
});

it("hand-edited block is restored on next sync", async () => {
  await run(1, blockV1, ["antigravity"]);
  writeFileSync(files.antigravity!.file, read("antigravity").replace("用中文回复", "随便"));
  expect(await run(1, blockV1, ["antigravity"])).toEqual({ antigravity: "written" });
  expect(read("antigravity")).toContain("用中文回复");
});

it("created file the user added to is kept on removal", async () => {
  await run(1, blockV1, ["claude_code"]);
  writeFileSync(files.claude_code!.file, `# added by me\n\n${read("claude_code")}`);
  await run(1, blockV1, []);
  expect(read("claude_code")).toBe("# added by me\n");
});

it("invalid block from server writes nothing", async () => {
  expect(await run(3, "<!-- memento:begin --> no end", ["claude_code"])).toEqual({ claude_code: "waiting: no published profile yet" });
  expect(existsSync(files.claude_code!.file)).toBe(false);
});

it("server-rendered block format is accepted", () => {
  const rendered =
    "<!-- memento:begin v7 · 由 Memento 生成，请在 Memento 中修改，手改此段会被覆盖 -->\n" +
    "## 关于我（Memento 长期记忆）\n\n### 沟通\n- 始终用中文回复\n\n" +
    "需要更多上下文时，用 memento-memory MCP 的 memory_search / memory_core 查询。\n" +
    "<!-- memento:end -->\n";
  expect(isValidProfileBlock(rendered)).toBe(true);
});
