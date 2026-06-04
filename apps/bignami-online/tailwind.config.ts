import type { Config } from "tailwindcss";
import baseConfig from "@perx/tailwind-config";

export default {
  presets: [baseConfig],
  content: [
    "./pages/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./app/**/*.{ts,tsx}",
    "./src/**/*.{ts,tsx}",
    "../../packages/ui/src/**/*.{ts,tsx}",
  ],
  prefix: "",
  theme: {
    extend: {
      colors: {
        primary: {
          hover: "hsl(var(--primary-hover))",
        },
        warning: {
          DEFAULT: "hsl(var(--warning))",
          foreground: "hsl(var(--warning-foreground))",
        },
        status: {
          draft: "hsl(var(--status-draft))",
          published: "hsl(var(--status-published))",
          pending: "hsl(var(--status-pending))",
          approved: "hsl(var(--status-approved))",
          rejected: "hsl(var(--status-rejected))",
        },
        badge: {
          frontespizio: "hsl(var(--badge-frontespizio))",
          comune: "hsl(var(--badge-comune))",
          raggruppata: "hsl(var(--badge-raggruppata))",
        },
        hover: {
          bg: "hsl(var(--hover-bg))",
        },
        active: {
          bg: "hsl(var(--active-bg))",
        },
      },
    },
  },
} satisfies Config;
