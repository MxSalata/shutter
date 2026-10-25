import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end tests run against the demo build (the in-browser mock of the REST API, with recorded cases), so they
 * need no IRIS instance and are deterministic.
 */
/** The preview's port: 4174, or E2E_PORT when runners that share one host each need their own. */
const port = Number(process.env.E2E_PORT || 4174);

export default defineConfig({
  testDir: './e2e',
  timeout: 45_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    ...(process.env.CHROMIUM_PATH ? { launchOptions: { executablePath: process.env.CHROMIUM_PATH } } : {}),
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: `npm run build:demo && npx vite preview --outDir dist-demo --port ${port} --strictPort`,
    url: `http://localhost:${port}`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
});
