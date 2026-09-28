import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, expect, it } from "vitest";

import { applySkillInjection, isValidSkillName, type SkillDirTarget } from "../src/skill-inject.js";

const md = (name: string, step: string) => `---\nname: ${name}\ndescription: "deploy it"\n---\n\n# ${name}\n\n1. ${step}\n`;

let tmp: string;
let dirs: Record<string, SkillDirTarget>;
let statePath: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "skill_inject_"));
  mkdirSync(join(tmp, ".claude"));
  dirs = {
    claude: { toolHomes: [join(tmp, ".claude")], dir: join(tmp, ".claude", "skills") },
    agents: { toolHomes: [join(tmp, ".codex")], dir: join(tmp, ".agents", "skills") },
  };
  statePath = join(tmp, "state.json");
});

afterEach(() => rmSync(tmp, { recursive: true, force: true }));

const run = (skills: Record<string, unknown>[], targets: string[]) => applySkillInjection({ skills, targets, dirs, statePath });
const skillFile = (dir: string, name: string) => join(tmp, dir, "skills", name, "SKILL.md");

it("names follow the Agent Skills rules", () => {
  expect(isValidSkillName("memento-gitops-deploy")).toBe(true);
  expect(isValidSkillName("Bad Name")).toBe(false);
  expect(isValidSkillName("double--hyphen")).toBe(false);
  expect(isValidSkillName("-leading")).toBe(false);
  expect(isValidSkillName("a".repeat(65))).toBe(false);
});

it("write, update, then remove when unpublished", async () => {
  expect((await run([{ slug: "deploy", version: 1, content: md("deploy", "push main") }], ["claude"]))["claude/deploy"]).toBe("written");
  expect(readFileSync(skillFile(".claude", "deploy"), "utf8")).toContain("push main");
  expect((await run([{ slug: "deploy", version: 1, content: md("deploy", "push main") }], ["claude"]))["claude/deploy"]).toBe("unchanged");
  const upd = await run([{ slug: "deploy", version: 2, content: md("deploy", "push main, then watch fleet") }], ["claude"]);
  expect(upd["claude/deploy"]).toBe("updated");
  expect(readFileSync(skillFile(".claude", "deploy"), "utf8")).toContain("watch fleet");
  expect((await run([], ["claude"]))["claude/deploy"]).toBe("removed");
  expect(existsSync(join(tmp, ".claude", "skills", "deploy"))).toBe(false);
});

it("a same-named skill the user made is never touched", async () => {
  const mine = skillFile(".claude", "deploy");
  mkdirSync(dirname(mine), { recursive: true });
  writeFileSync(mine, "my own skill");
  const out = await run([{ slug: "deploy", version: 1, content: md("deploy", "x") }], ["claude"]);
  expect(out["claude/deploy"]).toMatch(/^skipped/);
  expect(readFileSync(mine, "utf8")).toBe("my own skill");
  await run([], ["claude"]);
  expect(readFileSync(mine, "utf8")).toBe("my own skill");
});

it("a skill edited locally is kept, not overwritten or deleted", async () => {
  await run([{ slug: "deploy", version: 1, content: md("deploy", "a") }], ["claude"]);
  writeFileSync(skillFile(".claude", "deploy"), "edited by hand");
  expect((await run([{ slug: "deploy", version: 2, content: md("deploy", "b") }], ["claude"]))["claude/deploy"]).toBe("kept: edited locally");
  expect(readFileSync(skillFile(".claude", "deploy"), "utf8")).toBe("edited by hand");
  await run([], ["claude"]);
  expect(readFileSync(skillFile(".claude", "deploy"), "utf8")).toBe("edited by hand");
});

it("a folder for a tool that is not installed is skipped", async () => {
  const out = await run([{ slug: "deploy", version: 1, content: md("deploy", "a") }], ["agents"]);
  expect(out.agents).toBe("skipped: tool not installed");
  expect(existsSync(join(tmp, ".agents"))).toBe(false);
});

it("switching a tool off takes its skills back out, other folders stay", async () => {
  mkdirSync(join(tmp, ".codex"));
  const skills = [{ slug: "deploy", version: 1, content: md("deploy", "a") }];
  await run(skills, ["claude", "agents"]);
  expect(existsSync(skillFile(".agents", "deploy"))).toBe(true);
  const out = await run(skills, ["claude"]);
  expect(out["agents/deploy"]).toBe("removed");
  expect(existsSync(skillFile(".claude", "deploy"))).toBe(true);
});

it("invalid names are refused", async () => {
  const out = await run([{ slug: "../escape", version: 1, content: "x" }], ["claude"]);
  expect(out["claude/../escape"]).toBe("error: invalid skill");
  expect(existsSync(join(tmp, ".claude", "escape", "SKILL.md"))).toBe(false);
});
