import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { afterEach, beforeEach, expect, it } from "vitest";

import { TaskWorktree } from "../src/worktree.js";

const git = (cwd: string, ...args: string[]) =>
  execFileSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", ...args], { cwd, encoding: "utf8" });

let tmp: string;
let repo: string;
let home: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "worktree_test"));
  repo = join(tmp, "repo");
  home = join(tmp, "home");
  mkdirSync(join(repo, "server"), { recursive: true });
  writeFileSync(join(repo, "server", "app.py"), "print(1)\n");
  git(repo, "init", "-q");
  git(repo, "add", ".");
  git(repo, "commit", "-qm", "init");
});

afterEach(() => rmSync(tmp, { recursive: true, force: true }));

it("runs in the same subdirectory of its own worktree, outside the repo", async () => {
  const { tree } = await TaskWorktree.create(join(repo, "server"), "abcd1234-5678-90ef", { home });
  expect(tree!.branch).toBe("memento/abcd1234");
  expect(relative(repo, tree!.path).startsWith("..")).toBe(true);
  expect(tree!.workDir).toBe(join(tree!.path, "server"));
  expect(existsSync(join(tree!.workDir, "app.py"))).toBe(true);
});

it("a task that changed nothing leaves no worktree or branch behind", async () => {
  const { tree } = await TaskWorktree.create(repo, "task0001", { home });
  expect((await tree!.finish()).status).toBe("removed");
  expect(existsSync(tree!.path)).toBe(false);
  expect(git(repo, "branch", "--list", "memento/*").trim()).toBe("");
});

it("changes and commits keep the branch for review", async () => {
  const { tree } = await TaskWorktree.create(repo, "task0002", { home });
  writeFileSync(join(tree!.path, "server", "app.py"), "print(2)\n");
  git(tree!.path, "commit", "-qam", "change");
  writeFileSync(join(tree!.path, "new.txt"), "x");
  const result = await tree!.finish();
  expect(result).toMatchObject({ status: "kept", commits: 1, files: ["new.txt", "server/app.py"] });
  expect(existsSync(tree!.path)).toBe(true);
  // The main checkout is untouched.
  expect(readFileSync(join(repo, "server", "app.py"), "utf8")).toBe("print(1)\n");
});

it("outside a repository the task runs in place", async () => {
  const plain = join(tmp, "plain");
  mkdirSync(plain);
  const r = await TaskWorktree.create(plain, "task0003", { home });
  expect(r.tree).toBeNull();
  expect(r.reason).toContain("不是 git 仓库");
});
