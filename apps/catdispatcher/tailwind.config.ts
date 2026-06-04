import type { Config } from "tailwindcss";
import baseConfig from "../../packages/tailwind-config/index";

export default {
  presets: [baseConfig as unknown as Config],
  content: [
    "./pages/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./app/**/*.{ts,tsx}",
    "./src/**/*.{ts,tsx}",
    "../../packages/ui/src/**/*.{ts,tsx}",
  ],
  prefix: "",
} satisfies Config;
