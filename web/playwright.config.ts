import { defineConfig, devices } from '@playwright/test';

/**
 * End-to-end tests, in two projects:
 *
 * - `chromium`: the demo build, which is always the trial (the recorded mock answers in the browser), so the screens
 *   and flows need no IRIS instance and are deterministic;
 * - `iris-trial`: the build IRIS serves (`vite build --mode iris`), previewed at /shutter/ with no proxy and an
 *   instance address nothing listens on, so a call that escaped the trial could reach nothing; each test also stubs
 *   `/api/shutter` in the browser and records every hit. It proves the trial reaches no live system
 *   (e2e/trial.spec.ts), and audits the live sign-in page.
 */
/** The demo preview's port: 4174, or E2E_PORT when runners that share one host each need their own. */
const port = Number(process.env.E2E_PORT || 4174);
/** The IRIS build's preview: E2E_IRIS_PORT, or the demo's port plus 100. */
const irisPort = Number(process.env.E2E_IRIS_PORT || port + 100);

export default defineConfig({
  testDir: './e2e',
  timeout: 45_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    ...(process.env.CHROMIUM_PATH ? { launchOptions: { executablePath: process.env.CHROMIUM_PATH } } : {}),
  },
  projects: [
    {
      name: 'chromium',
      testIgnore: /trial\.spec\.ts$/,
      use: { ...devices['Desktop Chrome'], baseURL: `http://localhost:${port}` },
    },
    {
      name: 'iris-trial',
      testMatch: /trial\.spec\.ts$/,
      use: { ...devices['Desktop Chrome'], baseURL: `http://localhost:${irisPort}/shutter/` },
    },
  ],
  webServer: [
    {
      command: `npm run build:demo && npx vite preview --outDir dist-demo --port ${port} --strictPort`,
      url: `http://localhost:${port}`,
      reuseExistingServer: !process.env.CI,
      timeout: 180_000,
    },
    {
      command: `npx vite build --mode iris --outDir dist-iris-e2e --emptyOutDir && npx vite preview --mode iris --outDir dist-iris-e2e --port ${irisPort} --strictPort`,
      url: `http://localhost:${irisPort}/shutter/`,
      env: { VITE_IRIS_URL: 'http://127.0.0.1:9', E2E_NO_PROXY: '1' },
      reuseExistingServer: !process.env.CI,
      timeout: 180_000,
    },
  ],
});
