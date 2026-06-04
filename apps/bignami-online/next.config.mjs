import path from "node:path";
import { fileURLToPath } from "node:url";

const monorepoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["@perx/ui", "@perx/tailwind-config"],
  // The previous Vite production build did not run TypeScript validation.
  // Keep deploy parity until the generated Supabase query types are reconciled.
  typescript: {
    ignoreBuildErrors: true,
  },
  turbopack: {
    root: monorepoRoot,
  },
};

const packagesDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../packages");

function withPackageAliases(cfg) {
  const originalWebpack = cfg.webpack;
  cfg.webpack = (webpackConfig, options) => {
    webpackConfig.resolve.alias = {
      ...webpackConfig.resolve.alias,
      "@perx/ui": path.join(packagesDir, "ui/src"),
      "@perx/tailwind-config": path.join(packagesDir, "tailwind-config"),
    };
    return originalWebpack ? originalWebpack(webpackConfig, options) : webpackConfig;
  };
  return cfg;
}

export default withPackageAliases(nextConfig);
