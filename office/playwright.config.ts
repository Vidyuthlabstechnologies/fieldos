import { defineConfig } from '@playwright/test';

// Runs against a local FieldOS cloud: from the repo root,
//   supabase start -x realtime,imgproxy,edge-runtime,logflare,vector,supavisor,studio,mailpit
//   eval "$(supabase status -o env)"   # sets API_URL, ANON_KEY, SERVICE_ROLE_KEY
// then `npm run test:e2e` here. PW_CHROMIUM points at a ready-made browser
// when this machine has one.
const port = 5175;

export default defineConfig({
  testDir: 'e2e',
  timeout: 60_000,
  fullyParallel: false,
  use: {
    baseURL: `http://localhost:${port}/office/`,
    launchOptions: process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {},
  },
  webServer: {
    command: `npx vite --port ${port} --strictPort`,
    url: `http://localhost:${port}/office/`,
    reuseExistingServer: false,
    env: {
      VITE_SUPABASE_URL: process.env.API_URL ?? '',
      VITE_SUPABASE_ANON_KEY: process.env.ANON_KEY ?? '',
    },
  },
});
