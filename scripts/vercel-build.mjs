import { spawnSync } from "node:child_process";

const projectToWorkspace = {
  "bignami-online": "@perx/bignami-online",
  catdispatcher: "@perx/catdispatcher",
  "insight-studio": "@perx/insight-studio",
  perx: "@perx/portal-web",
  "perx-insight-studio": "@perx/insight-studio",
  "portal-web": "@perx/portal-web",
  randa: "@perx/randa",
};

const projectName = process.env.VERCEL_PROJECT_NAME;
const workspace =
  process.env.VERCEL_BUILD_WORKSPACE ??
  projectToWorkspace[projectName] ??
  "@perx/portal-web";

console.log(`Building ${workspace} for Vercel project ${projectName ?? "<missing>"}.`);

const result = spawnSync(
  "npx",
  ["turbo", "run", "build", `--filter=${workspace}`],
  { stdio: "inherit", shell: process.platform === "win32" },
);

process.exit(result.status ?? 1);
