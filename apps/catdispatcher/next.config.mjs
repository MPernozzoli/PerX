import path from "node:path";
import { fileURLToPath } from "node:url";

const monorepoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["@perx/ui", "@perx/tailwind-config"],
  turbopack: {
    root: monorepoRoot,
  },
};

export default nextConfig;
