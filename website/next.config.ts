import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Diagrams are local PNGs served from /public — no remote image config needed.
  // Static-exportable if ever needed (the site has no server-only features).
  reactStrictMode: true,
  // This app is self-contained; pin file tracing to it so Next doesn't pick the
  // repo-root lockfile (the AVS project) as the workspace root.
  outputFileTracingRoot: process.cwd(),
};

export default nextConfig;
