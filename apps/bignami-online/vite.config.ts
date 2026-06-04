import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
  },
  plugins: [react(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "@perx/ui/components/ui": path.resolve(__dirname, "../../packages/ui/src/components/ui"),
      "@perx/ui/lib/utils": path.resolve(__dirname, "../../packages/ui/src/lib/utils.ts"),
      "@perx/tailwind-config": path.resolve(__dirname, "../../packages/tailwind-config/index.ts"),
    },
  },
}));
