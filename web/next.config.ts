import path from "node:path";
import type { NextConfig } from "next";

// The repo is an npm workspace: dependencies (and @memento/core) live in the
// root node_modules, so tracing and bundling start from the repo root.
const repoRoot = path.join(__dirname, "..");

const nextConfig: NextConfig = {
  output: "standalone",
  outputFileTracingRoot: repoRoot,
  turbopack: { root: repoRoot },
};

export default nextConfig;
