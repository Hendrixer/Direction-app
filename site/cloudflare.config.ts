import { defineConfig } from "cf/config";

// The marketing site: static files in ./public (see wrangler.config.ts), served at givedirection.ai.
export default defineConfig({
  worker: {
    name: "direction-site",
    compatibilityDate: "2026-10-06",
    domains: ["givedirection.ai", "www.givedirection.ai"],
    observability: { enabled: true },
  },
});
