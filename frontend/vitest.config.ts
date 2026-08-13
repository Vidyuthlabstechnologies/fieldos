import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  resolve: {
    // Mirrors tsconfig.json's "@/*" path mapping -- Vitest/Vite doesn't read
    // tsconfig paths automatically, so without this, any "@/..." import
    // fails to resolve ("Failed to resolve import" / "Does the file exist?").
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./vitest.setup.ts",
  },
});
